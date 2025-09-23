import logging
import subprocess
import sys
import os
import zipfile
from pathlib import Path
from parameters import Parameters

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)


def main():
    params = Parameters()
    logger.info(f"Parameters: {params}")

    # Prepare arguments for tiling_main.sh
    input_file = params.dataset_path
    # Set environment variables that tiling_main.sh might need
    env = os.environ.copy()
    env["TILE_SIZE"] = str(params.tile_size)
    env["OVERLAP"] = str(params.overlap)

    # Call tiling_main.sh with appropriate arguments
    try:
        if params.task == "tile":
            logger.info("Running tiling & subsampling only")
            result = subprocess.run(
                ["bash", "tiling_main.sh", input_file, output_suffix],
                check=True,
                text=True,
                env=env,
            )
            logger.info("Tiling completed successfully")

            # Create zip file for tiling results
            with zipfile.ZipFile("/out/prepared_files.zip", "w") as zipf:
                zipf.write("/out/00_original", "00_original")
                zipf.write("/out/01_subsampled", "01_subsampled")
                zipf.write("/out/02_input_SAT", "02_input_SAT")

            logger.info("Zip file created successfully")

        elif params.task == "merge":
            logger.info("Running merge task and remapping to original resolution")

            with zipfile.ZipFile("/in/processed_files.zip", "r") as zf:
                zf.extractall("/out")
            logger.info("Unzip completed successfully")

            # Import and call the merge function directly
            from merge_tiles import merge_tiles

            # Set up paths for merge operation
            tile_folder = (
                "/out/03_output_SAT/final_results"  # Where the tiles are located
            )
            original_point_cloud = "/out/00_original/input.laz"  # Original input file

            os.makedirs("/out/04_merged", exist_ok=True)
            output_file = "/out/04_merged/merged_pc.laz"  # Output file

            merge_tiles(
                tile_folder=tile_folder,
                original_point_cloud=original_point_cloud,
                output_file=output_file,
                buffer=0,
                min_cluster_size=300,
            )
            logger.info("Merge completed successfully")

            # Add remapping step to original resolution
            logger.info("Starting remapping to original resolution...")
            from remapping_original_res import main as remap_main

            # Set up paths for remapping
            original_file = "/out/00_original/input.laz"  # Original high-res file
            subsampled_file = "/out/04_merged/merged_pc.laz"  # Merged subsampled file with predictions
            remapped_output = "/out/final_pc.laz"  # Final output

            remap_main(
                original_file=original_file,
                subsampled_file=subsampled_file,
                output_file=remapped_output,
            )
            logger.info("Remapping completed successfully")

        else:
            logger.error(f"Unknown task: {params.task}")
            sys.exit(1)

    except subprocess.CalledProcessError as e:
        logger.error(f"Script failed with return code {e.returncode}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
