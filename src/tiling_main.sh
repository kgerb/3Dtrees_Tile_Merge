#!/bin/bash
# limit memory
ulimit -v 188743680  # 200 GB in kilobytes (200 * 1024 * 1024)

# Get the input file argument
INPUT_FILE=$1
ORIGINAL_FILE=/out/00_original/input.laz

echo "Starting pipeline..." 

echo "[Step 0.5] Copying original file to /out/00_original"
mkdir -p /out/00_original
cp "$INPUT_FILE" "$ORIGINAL_FILE"

echo "[Step 1] Subsampling input file to 10cm: $INPUT_FILE ..." 

mkdir -p /out/01_subsampled
# Step 0: Subsample the input point cloud to 10 cm
SUBSAMPLED_10cm_FILE=/out/01_subsampled/input_subsampled_10cm.laz

pdal translate "/out/00_original/input.laz" "${SUBSAMPLED_10cm_FILE}" --json='{ 
    "pipeline": [ 
        { 
            "type": "filters.voxelcentroidnearestneighbor", 
            "cell": 0.10 
        }
    ]
}'


# Step 1: Tiling input file (if needed)
echo "[Step 2] Tiling input file: $SUBSAMPLED_10cm_FILE ..." 

# Check if the subsampled file is smaller than 3 GB
if [ $(stat -c%s "$SUBSAMPLED_10cm_FILE") -lt 3000000000 ]; then
    echo "Subsampled file is smaller than 3 GB. Copying it to 02_input_SAT folder..." 
    mkdir -p /out/02_input_SAT
    rsync -avP "$SUBSAMPLED_10cm_FILE" /out/02_input_SAT/tiled_1.laz
else
    echo "File is large, tiling with size $TILE_SIZE and overlap $OVERLAP"
    mkdir -p /out/02_input_SAT
    pdal tile "$SUBSAMPLED_10cm_FILE" /out/02_input_SAT/tiled_#.laz --length $TILE_SIZE --buffer $OVERLAP
    
    # Check if tiles are too large and tile them again
    echo "Checking if tiles are too large..."
    index=1
    for f in /out/02_input_SAT/*.laz; do
        if [ -f "$f" ] && [ $(stat -c%s "$f") -gt 2000000000 ]; then
            echo "Tile $f is too large. Tiling it again..." 
            pdal tile "$f" /out/02_input_SAT/tiled_again_${index}_#.laz --length $((($TILE_SIZE*2) / 3)) --buffer $OVERLAP 
            rm -f "$f" 
            index=$((index + 1))
        fi
    done

    # Remove tiles with less than 1000 points
    echo "Removing tiles with less than 1000 points..." 
    for tile in /out/02_input_SAT/*.laz; do
        if [ -f "$tile" ]; then
            point_count=$(pdal info --metadata "$tile" | grep '"count"' | sed 's/[^0-9]//g')
            echo "Tile $tile has $point_count points." 
            if [ "$point_count" -lt 1000 ]; then
                echo "Tile $tile has less than 1000 points. Deleting it..." 
                rm -f "$tile"
            fi
        fi
    done
fi

echo "Tiling completed"