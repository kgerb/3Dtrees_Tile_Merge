#!/bin/bash

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
if [ $(stat -c%s "$SUBSAMPLED_10cm_FILE") -lt $TILING_THRESHOLD ]; then
    echo "Subsampled file is smaller than 3 GB. Copying it to 02_input_SAT folder..." 
    mkdir -p /out/02_input_SAT
    rsync -avP "$SUBSAMPLED_10cm_FILE" /out/02_input_SAT/tiled_1.laz
else
    echo "File is large, tiling with size $TILE_SIZE and overlap $OVERLAP"
    mkdir -p /out/02_input_SAT
    pdal tile "$SUBSAMPLED_10cm_FILE" /out/02_input_SAT/tiled_#.laz --length $TILE_SIZE --buffer $OVERLAP
    
    # Check if tiles are too large and tile them again
    echo "Checking if tiles are too large - greater than 66% of threshold..."
    index=1
    for f in /out/02_input_SAT/*.laz; do
        if [ -f "$f" ] && [ $(stat -c%s "$f") -gt $TILE_AGAIN_THRESHOLD ]; then
            echo "Tile $f is too large. Tiling it again..." 
            # Calculate new tile size and buffer (must satisfy: buffer < length/2)
            NEW_TILE_SIZE=$((($TILE_SIZE*2) / 3))
            NEW_BUFFER=$((($OVERLAP*2) / 3))
            # Ensure buffer is less than half of tile size
            if [ $NEW_BUFFER -ge $(($NEW_TILE_SIZE / 2)) ]; then
                NEW_BUFFER=$(($NEW_TILE_SIZE / 2 - 1))
            fi
            echo "Re-tiling with size $NEW_TILE_SIZE and buffer $NEW_BUFFER"
            pdal tile "$f" /out/02_input_SAT/tiled_again_${index}_#.laz --length $NEW_TILE_SIZE --buffer $NEW_BUFFER 
            rm -f "$f" 
            index=$((index + 1))
        fi
    done

    # Remove tiles with less than threshold points
    echo "Removing tiles with less than $POINTS_THRESHOLD points..." 
    for tile in /out/02_input_SAT/*.laz; do
        if [ -f "$tile" ]; then
            point_count=$(pdal info --metadata "$tile" | grep '"count"' | sed 's/[^0-9]//g')
            echo "Tile $tile has $point_count points." 
            if [ "$point_count" -lt $POINTS_THRESHOLD ]; then
                echo "Tile $tile has less than $POINTS_THRESHOLD points. Deleting it..." 
                rm -f "$tile"
            fi
        fi
    done
fi

echo "Tiling completed"
