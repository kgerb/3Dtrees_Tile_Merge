from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, AliasChoices, field_validator
from pathlib import Path
from typing import Optional


class Parameters(BaseSettings):
    dataset_path: str = Field(
        "/in/pc_standardized.laz",
        description="Input dataset path",
        alias=AliasChoices("dataset-path", "dataset_path"),
    )
    output_dir: Path = Field(
        "/out",
        description="Output directory",
        alias=AliasChoices("output-dir", "output_dir"),
    )
    task: str = Field(
        "tile",
        description="Task to perform: Tile includes subsampling; Merge includes merging the tiles back and mapping to original resolution.",
    )

    # Parameters only required for 'tile' task
    tile_size: Optional[int] = Field(
        50,
        description="Tile size (only required for 'tile' task)",
        alias=AliasChoices("tile-size", "tile_size"),
    )
    overlap: Optional[int] = Field(
        20,
        description="Overlap (only required for 'tile' task)",
        alias=AliasChoices("overlap", "overlap"),
    )
    tiling_threshold: Optional[float] = Field(
        3.0,
        description="Tiling threshold in GB (only required for 'tile' task)",
        alias=AliasChoices("tiling-threshold", "tiling_threshold"),
    )
    points_threshold: Optional[int] = Field(
        1000,
        description="required min. points per tile - otherwise deleted (only required for 'tile' task)",
        alias=AliasChoices("points-threshold", "points_threshold"),
    )
    subsampling_resolution: Optional[int] = Field(
        10,
        description="Subsampling resolution in cm (only required for 'tile' task)",
        alias=AliasChoices("subsampling-resolution", "subsampling_resolution"),
    )
    number_of_threads: Optional[int] = Field(
        8,
        description="Number of threads enabled for this tool (only required for 'tile' task)",
        alias=AliasChoices("number-of-threads", "number_of_threads"),
    )
    min_cluster_size: Optional[int] = Field(
        300,
        description="Minimum cluster size (only required for 'merge' task)",
        alias=AliasChoices("min-cluster-size", "min_cluster_size"),
    )
    initial_radius: Optional[float] = Field(
        1.0,
        description="Initial radius (only required for 'merge' task)",
        alias=AliasChoices("initial-radius", "initial_radius"),
    )
    max_radius: Optional[float] = Field(
        5.0,
        description="Maximum radius (only required for 'merge' task)",
        alias=AliasChoices("max-radius", "max_radius"),
    )
    radius_step: Optional[float] = Field(
        1.0,
        description="Radius step (only required for 'merge' task)",
        alias=AliasChoices("radius-step", "radius_step"),
    )
    buffer: Optional[float] = Field(
        0.0,
        description="Buffer [m] (only required for 'merge' task)",
        alias=AliasChoices("buffer", "buffer"),
    )

    @field_validator(
        "tile_size",
        "overlap",
        "tiling_threshold",
        "points_threshold",
        "subsampling_resolution",
        "number_of_threads",
    )
    @classmethod
    def validate_tile_params(cls, v, info):
        """Validate that tiling parameters are provided when task is 'tile'"""
        if info.data.get("task") == "tile" and v is None:
            raise ValueError(f"{info.field_name} is required when task is 'tile'")
        return v

    @field_validator(
        "min_cluster_size",
        "initial_radius",
        "max_radius",
        "radius_step",
        "buffer",
    )
    @classmethod
    def validate_merge_params(cls, v, info):
        """Validate that merge parameters are provided when task is 'merge'"""
        if info.data.get("task") == "merge" and v is None:
            raise ValueError(f"{info.field_name} is required when task is 'merge'")
        return v

    model_config = SettingsConfigDict(
        case_sensitive=False, cli_parse_args=True, cli_ignore_unknown_args=True
    )
