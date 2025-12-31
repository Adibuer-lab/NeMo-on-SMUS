# syntax=__DOCKERFILE_FRONTEND__
FROM __LLMFT_BASE_IMAGE__


ARG GDRCOPY_VERSION=v2.4.1
ARG EFA_INSTALLER_VERSION=1.45.1
ARG AWS_OFI_NCCL_VERSION=v1.17.2
ARG NCCL_VERSION=v2.27.7
ARG NCCL_TESTS_VERSION=v2.13.10
ARG TRANSFORMERS_VERSION=4.48.1
ARG TRANSFORMER_ENGINE_VERSION=1.10.0
ARG TRANSFORMER_ENGINE_INDEX_URL=https://pypi.nvidia.com
ARG FLASH_ATTN_VERSION=2.4.2
ARG FLASH_ATTN_BUILD_JOBS=16
ARG FLASH_ATTN_CUDA_ARCH_LIST=80;90
ARG FLASH_ATTN_TORCH=2.4
ARG FLASH_ATTN_CUDA=cu12
ARG BUILD_JOBS=32
ARG SMP_PYTORCH_VERSION=2.4.1
ARG SMP_PYTORCH_BUILD=sm_py3.11_cuda12.1_cudnn9.4.0_nccl_pt_2.4_tsm_2.7_smp_2.7.0_cuda12.1_0
ARG SMDDP_WHL_URL=https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.4.1/cu121/2024-10-09/smdistributed_dataparallel-2.5.0-cp311-cp311-linux_x86_64.whl
ARG OPEN_MPI_PATH=/opt/amazon/openmpi
ARG ADAPTER_CACHE_BUST=0

ENV UV_PYTHON=/opt/conda/bin/python3.11 \
    UV_CONCURRENT_BUILDS=${BUILD_JOBS} \
    UV_CONCURRENT_INSTALLS=${BUILD_JOBS} \
    UV_CONCURRENT_DOWNLOADS=32 \
    UV_CACHE_DIR=/root/.cache/uv

######################
# Update and remove IB libverbs
######################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update -y && apt-get upgrade -y
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get remove -y --allow-change-held-packages \
    ibverbs-utils \
    libibverbs-dev \
    libibverbs1 \
    libmlx5-1

RUN rm -rf /opt/hpcx/ompi \
    && rm -rf /usr/local/mpi \
    && rm -rf /usr/local/ucx \
    && ldconfig

######################
# Install build dependencies
######################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-unauthenticated \
    apt-utils \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    gcc \
    gdb \
    git \
    kmod \
    libtool \
    openssh-client \
    openssh-server \
    vim \
    && apt-get autoremove -y

######################
# Configure SSH
######################
RUN mkdir -p /var/run/sshd && \
    sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

RUN rm -rf /root/.ssh/ \
    && mkdir -p /root/.ssh/ \
    && ssh-keygen -q -t rsa -N '' -f /root/.ssh/id_rsa \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys \
    && printf "Host *\n  StrictHostKeyChecking no\n" >> /root/.ssh/config

######################
# Set environment variables
######################
ENV LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/conda/bin:/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

######################
# Configure conda/mamba parallelism
######################
RUN /opt/conda/bin/conda config --set default_threads ${BUILD_JOBS} \
    && /opt/conda/bin/conda config --set repodata_threads ${BUILD_JOBS} \
    && /opt/conda/bin/conda config --set execute_threads ${BUILD_JOBS} \
    && /opt/conda/bin/conda config --set verify_threads ${BUILD_JOBS}

######################
# Install libcheck
######################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        check pkg-config

######################
# Install NVIDIA GDRCopy
######################
RUN git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make -j ${BUILD_JOBS} prefix=/opt/gdrcopy install \
    && rm -rf /tmp/gdrcopy

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/lib64:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat/:$LIBRARY_PATH
ENV CPATH=/opt/gdrcopy/include:$CPATH
ENV PATH=/opt/gdrcopy/bin:$PATH

######################
# Install EFA installer
######################
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

######################
# Install AWS-OFI-NCCL plugin
######################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y libhwloc-dev

SHELL ["/bin/bash", "-c"]
RUN curl -OL https://github.com/aws/aws-ofi-nccl/releases/download/${AWS_OFI_NCCL_VERSION}/aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && tar -xf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && cd aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws \
    && make -j ${BUILD_JOBS} \
    && make install \
    && cd .. \
    && rm -rf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && rm aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz

SHELL ["/bin/sh", "-c"]

######################
# Cleanup and configure MPI
######################
RUN rm -rf /var/lib/apt/lists/*

RUN echo "hwloc_base_binding_policy = none" >> /opt/amazon/openmpi/etc/openmpi-mca-params.conf \
    && echo "rmaps_base_mapping_policy = slot" >> /opt/amazon/openmpi/etc/openmpi-mca-params.conf

######################
# Install Python dependencies
######################
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/python -m pip install uv \
    && /opt/conda/bin/uv pip install --system \
        awscli==1.44.7 \
        boto3==1.42.17 \
        sagemaker==3.3.0 \
        pynvml \
        wandb \
        onnx==1.16.2 \
        jinja2>=3.1 \
        attrs \
        einops \
        importlib-metadata \
        ninja \
        packaging \
        pydantic \
        transformers==${TRANSFORMERS_VERSION} \
        sentencepiece \
        python-etcd \
        nemo-run==0.4.0 \
        nemo-toolkit \
        nemoguardrails \
        hyperpod-elastic-agent==1.1.0 \
        skypilot-nightly[kubernetes] \
        pytorch-lightning \
        s3torchconnector 

######################
# Install SageMaker HyperPod training adapter for NeMo from source (before SMP torch swap)
######################
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    echo "adapter-cache-bust=${ADAPTER_CACHE_BUST}" \
    && git clone --branch dev --single-branch https://github.com/Adibuer-lab/sagemaker-hyperpod-training-adapter-for-nemo.git /opt/hyperpod-adapter \
    && cd /opt/hyperpod-adapter \
    && /opt/conda/bin/uv pip install --system ".[all]"

######################
# Prepare conda tooling and cuDNN
######################
RUN --mount=type=cache,target=/opt/conda/pkgs \
    /opt/conda/bin/conda install -y -c conda-forge mamba

RUN --mount=type=cache,target=/opt/conda/pkgs \
    /opt/conda/bin/conda install -y conda-build \
    && mkdir -p /tmp/aws-ofi-nccl \
    && printf '%s\n' \
        'package:' \
        '  name: aws-ofi-nccl' \
        '  version: 1.7.1' \
        'build:' \
        '  number: 0' \
        '  noarch: generic' \
        '  script: |' \
        '    mkdir -p $PREFIX/opt/aws-ofi-nccl' \
        '    echo "system install" > $PREFIX/opt/aws-ofi-nccl/README' \
        'about:' \
        '  summary: "Placeholder for system-installed aws-ofi-nccl"' \
        > /tmp/aws-ofi-nccl/meta.yaml \
    && /opt/conda/bin/conda build /tmp/aws-ofi-nccl \
    && /opt/conda/bin/conda install -y --use-local aws-ofi-nccl=1.7.1 \
    && /opt/conda/bin/conda remove -y conda-build \
    && rm -rf /tmp/aws-ofi-nccl

RUN --mount=type=cache,target=/opt/conda/pkgs \
    /opt/conda/bin/mamba install -y "cudnn>=9,<10" -c conda-forge

RUN test -f /opt/conda/include/cudnn.h \
    && mkdir -p /usr/local/cuda/include /usr/local/cuda/lib64 \
    && ln -sf /opt/conda/include/cudnn*.h /usr/local/cuda/include/ \
    && ln -sf /opt/conda/lib/libcudnn* /usr/local/cuda/lib64/

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/python -m pip install uv \
    && /opt/conda/bin/uv pip install --system \
        megatron-core==0.11.0

# Reinstall Jinja2 after conda-build removal to ensure the package files exist
RUN /opt/conda/bin/python -m pip install --force-reinstall "markupsafe>=2.0" "jinja2>=3.1" \
    && /opt/conda/bin/python -c "import jinja2; from jinja2.ext import Extension; print('jinja2', jinja2.__version__); print('Extension', Extension)"

######################
# Remove pip-installed torch stack before installing SMP torch
######################
RUN /opt/conda/bin/python -m pip uninstall -y \
        torch \
        torchvision \
        torchaudio \
        torchdata \
        triton \
        nvidia-cublas-cu12 \
        nvidia-cuda-cupti-cu12 \
        nvidia-cuda-nvrtc-cu12 \
        nvidia-cuda-runtime-cu12 \
        nvidia-cudnn-cu12 \
        nvidia-cufft-cu12 \
        nvidia-cufile-cu12 \
        nvidia-curand-cu12 \
        nvidia-cusolver-cu12 \
        nvidia-cusparse-cu12 \
        nvidia-cusparselt-cu12 \
        nvidia-nccl-cu12 \
        nvidia-nvjitlink-cu12 \
        nvidia-nvshmem-cu12 \
        nvidia-nvtx-cu12 \
    || true

######################
# Install SMP-enabled PyTorch (torch.sagemaker) from SMP v2 conda channel
######################
RUN --mount=type=cache,target=/opt/conda/pkgs \
    /opt/conda/bin/mamba install -y \
        "pytorch=${SMP_PYTORCH_VERSION}=${SMP_PYTORCH_BUILD}" \
        --override-channels \
        -c file:///opt/conda/conda-bld \
        -c https://sagemaker-distributed-model-parallel.s3.us-west-2.amazonaws.com/smp-v2/ \
        -c pytorch -c nvidia -c conda-forge

RUN /opt/conda/bin/python -c "import importlib.util, torch; assert importlib.util.find_spec('torch.sagemaker'), 'torch.sagemaker missing after SMP install'"

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    CUDA_HOME=/usr/local/cuda \
    CUDNN_PATH=/opt/conda \
    CUDNN_LIBRARY=/opt/conda/lib \
    CUDNN_INCLUDE_DIR=/opt/conda/include \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/conda/lib:$LD_LIBRARY_PATH \
    TORCH_CUDA_ARCH_LIST=${FLASH_ATTN_CUDA_ARCH_LIST} \
    MAX_JOBS=${FLASH_ATTN_BUILD_JOBS} \
    CMAKE_BUILD_PARALLEL_LEVEL=${FLASH_ATTN_BUILD_JOBS} \
    NVCC_THREADS=1 \
    /opt/conda/bin/uv pip install --system --no-build-isolation --no-deps \
        "flash-attn==${FLASH_ATTN_VERSION}"

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    CUDA_HOME=/usr/local/cuda \
    CUDNN_PATH=/opt/conda \
    CUDNN_LIBRARY=/opt/conda/lib \
    CUDNN_INCLUDE_DIR=/opt/conda/include \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/conda/lib:$LD_LIBRARY_PATH \
    NVTE_FRAMEWORK=pytorch \
    MAX_JOBS=${BUILD_JOBS} \
    CMAKE_BUILD_PARALLEL_LEVEL=${BUILD_JOBS} \
    NVTE_BUILD_THREADS_PER_JOB=1 \
    /opt/conda/bin/uv pip install --system --no-build-isolation --no-deps \
        --extra-index-url ${TRANSFORMER_ENGINE_INDEX_URL} \
        "transformer_engine==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine_cu12==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine_torch==${TRANSFORMER_ENGINE_VERSION}"

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/uv pip install --system --no-deps ${SMDDP_WHL_URL}


RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/python -m pip install uv \
    && /opt/conda/bin/uv pip install --system \
        attrs \
        aiobotocore

# Patch torch.sagemaker TE version parsing (late layer to avoid full rebuild)
RUN /opt/conda/bin/python -c "from pathlib import Path; p=Path('/opt/conda/lib/python3.11/site-packages/torch/sagemaker/patches/patch_manager.py'); t=p.read_text(); \
old1='def get_loose_version(self, cur_TE_version_commit_id: str):\\n        \"\"\"\\n        Returns the loose TE version.\\n        \"\"\"\\n        version, commit_id = cur_TE_version_commit_id.split(\"+\")\\n        return version\\n'; \
new1='def get_loose_version(self, cur_TE_version_commit_id: str):\\n        \"\"\"\\n        Returns the loose TE version.\\n        \"\"\"\\n        if \"+\" in cur_TE_version_commit_id:\\n            version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n            return version\\n        return cur_TE_version_commit_id\\n'; \
old2='def get_loose_version(cur_TE_version_commit_id: str) -> str:\\n    version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n    return version\\n'; \
new2='def get_loose_version(cur_TE_version_commit_id: str) -> str:\\n    if \"+\" in cur_TE_version_commit_id:\\n        version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n        return version\\n    return cur_TE_version_commit_id\\n'; \
cond=('return cur_TE_version_commit_id' in t); \
p.write_text(t.replace(old1, new1).replace(old2, new2)) if (old1 in t or old2 in t) else print('patch_manager.py already patched.') if cond else print('patch_manager.py format changed; no update applied.')"

######################
# Configure MPI wrapper
######################
RUN mv $OPEN_MPI_PATH/bin/mpirun $OPEN_MPI_PATH/bin/mpirun.real \
    && echo '#!/bin/bash' > $OPEN_MPI_PATH/bin/mpirun \
    && echo '/opt/amazon/openmpi/bin/mpirun.real "$@"' >> $OPEN_MPI_PATH/bin/mpirun \
    && chmod a+x $OPEN_MPI_PATH/bin/mpirun

######################
# Set MPI environment variables
######################
ENV OMPI_MCA_pml=^cm,ucx \
    OMPI_MCA_btl=tcp,self \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent \
    OPAL_PREFIX=/opt/amazon/openmpi \
    NCCL_SOCKET_IFNAME=^docker,lo,veth \
    PMIX_MCA_gds=hash

WORKDIR /workspace
