import logging
import subprocess
import sys
import os
import zipfile
import time
from parameters import Parameters

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
# Add console handler
handler = logging.StreamHandler()
handler.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)


def main():
    start_time = time.time()
    params = Parameters()
    logger.info(f"Parameters: {params}")

    # Prepare arguments for tiling_main.sh
    input_file = params.dataset_path
    # Set environment variables that tiling_main.sh needs
    env = os.environ.copy()

    if params.task == "tile":
        env["TILE_SIZE"] = str(params.tile_size)
        env["OVERLAP"] = str(params.overlap)
        env["TILING_THRESHOLD"] = str(int(params.tiling_threshold * 1024 * 1024 * 1024))
        env["TILE_AGAIN_THRESHOLD"] = str(
            int(params.tiling_threshold * 1024 * 1024 * 1024 * (66 / 100))
        )
        env["SUBSAMPLING_RESOLUTION"] = str(
            f"{params.subsampling_resolution / 100:.2f}"
        )
        env["POINTS_THRESHOLD"] = str(params.points_threshold)
        env["NUMBER_OF_THREADS"] = str(params.number_of_threads)

    # Call tiling_main.sh with appropriate arguments
    try:
        if params.task == "tile":
            logger.info("Running tiling & subsampling only")
            subprocess.run(
                ["bash", "/src/tiling_main.sh", input_file],
                check=True,
                text=True,
                env=env,
                cwd="/src/",
            )
            logger.info("Tiling completed successfully")

            # Create zip file for tiling results
            logger.info("Creating zip file with tiling results...")
            with zipfile.ZipFile(
                "prepared_files.zip", "w"
            ) as zipf:  # Changed from "/out/prepared_files.zip" to "prepared_files.zip"
                # Add all files from each directory recursively
                directories_to_zip = [
                    "/out/00_original",
                    "/out/01_subsampled",
                    "/out/02_input_SAT",
                ]

                for directory in directories_to_zip:
                    if os.path.exists(directory):
                        for root, dirs, files in os.walk(directory):
                            for file in files:
                                file_path = os.path.join(root, file)
                                # Create relative path from /out/ for the archive
                                arcname = os.path.relpath(file_path, "/out")
                                zipf.write(file_path, arcname)
                                logger.info(f"Added to zip: {arcname}")
                    else:
                        logger.warning(f"Directory {directory} does not exist")

            logger.info("Zip file created successfully")

        elif params.task == "merge":
            logger.info("Running merge task and remapping to original resolution")

            with zipfile.ZipFile(input_file, "r") as zf:
                zf.extractall("/out")
            logger.info("Unzip completed successfully")

            # Import and call the merge function directly
            from merge_tiles import merge_tiles

            # Set up paths for merge operation
            tile_folder = (
                "/out/03_output_SAT/final_results"  # Where the tiles are located
            )
            subsampled_file = (
                "/out/01_subsampled/input_subsampled.laz"  # Subsampled input file
            )

            os.makedirs("/out/04_merged", exist_ok=True)
            output_file = "/out/04_merged/merged_pc.laz"  # Output file

            merge_tiles(
                tile_folder=tile_folder,
                original_point_cloud=subsampled_file,
                output_file=output_file,
                buffer=params.buffer,
                min_cluster_size=params.min_cluster_size,
                initial_radius=params.initial_radius,
                max_radius=params.max_radius,
                radius_step=params.radius_step,
            )
            logger.info("Merge completed successfully")

            # Add remapping step to original resolution
            logger.info("Starting remapping to original resolution...")
            from remapping_original_res import main as remap_main

            # Set up paths for remapping
            original_file = "/out/00_original/input.laz"  # Original high-res file
            subsampled_file = "/out/04_merged/merged_pc.laz"  # Merged subsampled file with predictions
            remapped_output = "segmented.laz"  # Final output

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

    end_time = time.time()
    logger.info(f"Total time taken: {end_time - start_time:.2f} seconds")


if __name__ == "__main__":
    main()
