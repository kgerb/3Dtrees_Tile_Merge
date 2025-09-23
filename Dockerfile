FROM nvidia/cuda:11.1.1-cudnn8-devel-ubuntu20.04

# Step 1: Install core dependencies (rarely changes)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    ca-certificates \
    python3 \
    python3-pip \
    python3-dev \
    rsync \
    util-linux \
    coreutils \
    bzip2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Step 2: Install Miniconda (rarely changes)
ENV CONDA_DIR=/opt/conda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p $CONDA_DIR && \
    rm miniconda.sh
ENV PATH=$CONDA_DIR/bin:$PATH

# Accept conda Terms of Service first
RUN conda config --set channel_priority strict && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Step 3: Copy environment file FIRST (only rebuilds if env file changes)
COPY ./src/tiling_env.yml .

# Create tiling environment using conda
RUN conda env create -f tiling_env.yml -n tiling_env && \
    conda clean -afy && \
    rm tiling_env.yml

# Environment setup (fast operations)
ENV PROJ_DATA=$CONDA_DIR/envs/tiling_env/share/proj
ENV PROJ_LIB=$CONDA_DIR/envs/tiling_env/share/proj
ENV PATH=$CONDA_DIR/envs/tiling_env/bin:$PATH
ENV CONDA_DEFAULT_ENV=tiling_env
ENV CONDA_PREFIX=$CONDA_DIR/envs/tiling_env

RUN echo "source activate tiling_env" >> ~/.bashrc
SHELL ["conda", "run", "-n", "tiling_env", "/bin/bash", "-c"]

# Install additional Python packages
RUN pip install \
    pydantic \
    pydantic-settings \
    tqdm

ENV EGL_PLATFORM=surfaceless

RUN mkdir -p /src && mkdir -p /in && mkdir -p /out
RUN chmod 777 /src /in /out
COPY ./src /src

WORKDIR /src
CMD ["python", "run.py"]