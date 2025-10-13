#!/bin/bash

# Get the input file argument
INPUT_FILE=$1
ORIGINAL_FILE=/out/00_original/input.laz

echo "Starting pipeline..." 

echo "TILE_SIZE: $TILE_SIZE"
echo "OVERLAP: $OVERLAP"
echo "TILING_THRESHOLD: $TILING_THRESHOLD"
echo "TILE_AGAIN_THRESHOLD: $TILE_AGAIN_THRESHOLD"
echo "POINTS_THRESHOLD: $POINTS_THRESHOLD"
echo "SUBSAMPLING_RESOLUTION: ${SUBSAMPLING_RESOLUTION}"

echo "[Step 0.5] Copying original file to /out/00_original"
mkdir -p /out/00_original
cp "$INPUT_FILE" "$ORIGINAL_FILE"

echo "[Step 1] Subsampling input file in parallel chunks..."

# Validate NUMBER_OF_THREADS
if [ -z "$NUMBER_OF_THREADS" ] || [ "$NUMBER_OF_THREADS" -lt 1 ]; then
    echo "ERROR: NUMBER_OF_THREADS must be set to a positive integer. Current value: '$NUMBER_OF_THREADS'"
    exit 1
fi

mkdir -p /out/01_subsampled
mkdir -p /out/01_subsampled/chunks
SUBSAMPLED_10cm_FILE=/out/01_subsampled/input_subsampled_10cm.laz

# Get the bounds of the input file
echo "Getting spatial bounds of input file..."
METADATA=$(pdal info --metadata "$ORIGINAL_FILE")
MINX=$(echo "$METADATA" | grep -oP '"minx":\s*\K[0-9.-]+' | head -1)
MAXX=$(echo "$METADATA" | grep -oP '"maxx":\s*\K[0-9.-]+' | head -1)
MINY=$(echo "$METADATA" | grep -oP '"miny":\s*\K[0-9.-]+' | head -1)
MAXY=$(echo "$METADATA" | grep -oP '"maxy":\s*\K[0-9.-]+' | head -1)

echo "Bounds: minx=$MINX, maxx=$MAXX, miny=$MINY, maxy=$MAXY"

# Validate bounds extraction
if [ -z "$MINX" ] || [ -z "$MAXX" ] || [ -z "$MINY" ] || [ -z "$MAXY" ]; then
    echo "ERROR: Failed to extract bounds from file. Check if file is valid."
    exit 1
fi

# Calculate chunk size based on number of threads
# We'll split along the X axis for simplicity
X_RANGE=$(echo "$MAXX - $MINX" | bc)
CHUNK_SIZE=$(echo "$X_RANGE / $NUMBER_OF_THREADS" | bc -l)

# Align chunk size to voxel grid to avoid boundary issues
# Round chunk size up to nearest multiple of voxel size
CHUNK_SIZE_ALIGNED=$(echo "scale=10; tmp = $CHUNK_SIZE / $SUBSAMPLING_RESOLUTION; scale=0; (tmp + 0.999999)/1 * $SUBSAMPLING_RESOLUTION" | bc)

echo "Raw chunk size: $CHUNK_SIZE, Aligned to voxel grid: $CHUNK_SIZE_ALIGNED (voxel size: $SUBSAMPLING_RESOLUTION)"
echo "Splitting into $NUMBER_OF_THREADS chunks along X axis"

# Align MINX to voxel grid as well for consistent grid origin (floor operation)
MINX_ALIGNED=$(echo "scale=10; tmp = $MINX / $SUBSAMPLING_RESOLUTION; scale=0; if (tmp < 0) tmp = (tmp - 0.999999)/1 else tmp = tmp/1; tmp * $SUBSAMPLING_RESOLUTION" | bc)

# Create and process chunks in parallel
pids=()
for i in $(seq 0 $((NUMBER_OF_THREADS - 1))); do
    CHUNK_MINX=$(echo "$MINX_ALIGNED + ($i * $CHUNK_SIZE_ALIGNED)" | bc -l)
    CHUNK_MAXX=$(echo "$MINX_ALIGNED + (($i + 1) * $CHUNK_SIZE_ALIGNED)" | bc -l)
    
    # For the last chunk, ensure we capture everything up to MAXX (and slightly beyond to be safe)
    if [ $i -eq $((NUMBER_OF_THREADS - 1)) ]; then
        CHUNK_MAXX=$(echo "$MAXX + $SUBSAMPLING_RESOLUTION" | bc -l)
    fi
    
    CHUNK_FILE="/out/01_subsampled/chunks/chunk_${i}.laz"
    
    echo "Processing chunk $i: x range [$CHUNK_MINX, $CHUNK_MAXX]"
    
    # Process chunk in background
    (
        pdal translate "$ORIGINAL_FILE" "$CHUNK_FILE" \
          --json="{\"pipeline\":[
            {\"type\":\"filters.crop\",\"bounds\":\"([$CHUNK_MINX,$CHUNK_MAXX],[$MINY,$MAXY])\"},
            {\"type\":\"filters.voxelcentroidnearestneighbor\",\"cell\":$SUBSAMPLING_RESOLUTION}
          ]}"
    ) &
    
    pids+=($!)
done

# Wait for all parallel processes to complete with progress tracking
echo "Waiting for all $NUMBER_OF_THREADS chunks to complete processing..."
completed=0
total=$NUMBER_OF_THREADS

for i in "${!pids[@]}"; do
    pid=${pids[$i]}
    wait $pid
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "Error: Chunk $i processing failed (PID $pid, exit code: $exit_code)"
        exit 1
    fi
    
    completed=$((completed + 1))
    percentage=$((completed * 100 / total))
    echo "✓ Chunk $i completed ($completed/$total, ${percentage}%)"
done

echo "All chunks completed successfully!"

echo ""
echo "Chunk processing summary:"
echo "========================="
total_points=0
for i in $(seq 0 $((NUMBER_OF_THREADS - 1))); do
    CHUNK_FILE="/out/01_subsampled/chunks/chunk_${i}.laz"
    if [ -f "$CHUNK_FILE" ]; then
        size=$(stat -c%s "$CHUNK_FILE" | awk '{printf "%.2f MB", $1/1024/1024}')
        points=$(pdal info --metadata "$CHUNK_FILE" 2>/dev/null | grep -m1 '"count"' | grep -oP '\d+')
        if [ -n "$points" ]; then
            total_points=$((total_points + points))
            echo "  Chunk $i: $size, $points points"
        else
            echo "  Chunk $i: $size"
        fi
    fi
done
echo "  Total points: $total_points"
echo "========================="
echo ""

echo "Merging chunks back together..."

# Merge all chunks back together
CHUNK_FILES=$(ls /out/01_subsampled/chunks/chunk_*.laz 2>/dev/null | tr '\n' ' ')
if [ -z "$CHUNK_FILES" ]; then
    echo "ERROR: No chunk files found to merge!"
    exit 1
fi

pdal merge $CHUNK_FILES "$SUBSAMPLED_10cm_FILE"

# Clean up chunk files
echo "Cleaning up temporary chunk files..."
rm -rf /out/01_subsampled/chunks

echo "Subsampling completed!"


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
