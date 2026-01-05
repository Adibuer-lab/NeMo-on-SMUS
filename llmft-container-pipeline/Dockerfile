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
ARG BUILD_JOBS=36
ARG SMP_PYTORCH_VERSION=2.5.1
ARG SMP_PYTORCH_BUILD=sm_py3.11_cuda12.4_cudnn9.4.0_nccl_pt_2.5_tsm_2.8_smp_2.8.0_cuda12.4_0
ARG SMDDP_WHL_URL=https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.4.1/cu121/2024-10-09/smdistributed_dataparallel-2.5.0-cp311-cp311-linux_x86_64.whl
ARG OPEN_MPI_PATH=/opt/amazon/openmpi
ARG ADAPTER_CACHE_BUST=15

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
        psutil \
        wandb==0.20.1 \
        onnx==1.16.2 \
        jinja2>=3.1 \
        attrs \
        einops \
        importlib-metadata \
        ninja \
        packaging \
        pydantic==2.12.5 \
        protobuf==4.24.4 \
        transformers==${TRANSFORMERS_VERSION} \
        sentencepiece \
        python-etcd \
        "nemo_run @ git+https://github.com/NVIDIA-NeMo/Run.git@7fc5426b16fbfb6020238986366faee6fe9b6138" \
        nv-one-logger-core==2.3.1 \
        nv-one-logger-training-telemetry==2.3.1 \
        nv-one-logger-pytorch-lightning-integration==2.3.1 \
        nv-one-logger-otel==2.3.1 \
        nemoguardrails \
        hyperpod-elastic-agent==1.1.0 \
        skypilot-nightly[kubernetes] \
        lightning==2.3.3 \
        pytorch-lightning==2.3.3 \
        torchmetrics==1.8.2 \
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

## Note: cuDNN is pulled in by the SMP PyTorch conda package with a pinned,
## CUDA-matched version (per SMP build string). Avoid installing a newer
## conda-forge cuDNN here to prevent ABI mismatches with CUDA libs.

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

# Remove conda-provided cuDNN/CUDA meta packages that can drift to 13.x.
RUN --mount=type=cache,target=/opt/conda/pkgs \
    /opt/conda/bin/mamba remove -y cudnn libcudnn libcudnn-dev cuda-opencl cuda-version || true \
    && /opt/conda/bin/mamba install -y "cuda-version=12.4.*" -c nvidia -c conda-forge

# Install cuDNN from NVIDIA's Debian repo (runtime + dev headers).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -e; \
    . /etc/os-release; \
    distro="ubuntu$(printf %s "$VERSION_ID" | tr -d '.')"; \
    arch="x86_64"; \
    curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${arch}/cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb; \
    dpkg -i /tmp/cuda-keyring.deb; \
    rm -f /tmp/cuda-keyring.deb; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libcudnn9-cuda-12 \
        libcudnn9-dev-cuda-12; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Prefer the conda CUDA runtime libs; cuDNN comes from system packages.
ENV LD_LIBRARY_PATH=/opt/conda/lib:/usr/lib/x86_64-linux-gnu:/usr/local/cuda/targets/x86_64-linux/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Sanity-check CUDA version and cuDNN presence (bash).
RUN set -e; \
    cuda_meta=$(ls /opt/conda/conda-meta/cuda-version-*.json 2>/dev/null | head -n1); \
    [ -n "$cuda_meta" ] || { echo "cuda-version package not found in /opt/conda/conda-meta" >&2; exit 1; }; \
    cuda_ver=$(basename "$cuda_meta" | sed 's/^cuda-version-//; s/-.*//'); \
    [ -n "$cuda_ver" ] || { echo "Failed to parse cuda-version from $cuda_meta" >&2; exit 1; }; \
    case "$cuda_ver" in 12.4*) ;; *) echo "Unexpected cuda-version=$cuda_ver (expected 12.4.x)" >&2; exit 1;; esac; \
    if [ ! -f /usr/lib/x86_64-linux-gnu/libcudnn.so.9 ]; then \
        echo "Missing /usr/lib/x86_64-linux-gnu/libcudnn.so.9; available libcudnn files:" >&2; \
        ls -l /usr/lib/x86_64-linux-gnu/libcudnn.so* >&2 || true; \
        exit 1; \
    fi; \
    if [ ! -f /usr/lib/x86_64-linux-gnu/libcudnn_graph.so.9 ]; then \
        echo "Missing /usr/lib/x86_64-linux-gnu/libcudnn_graph.so.9; available libcudnn_graph files:" >&2; \
        ls -l /usr/lib/x86_64-linux-gnu/libcudnn_graph.so* >&2 || true; \
        exit 1; \
    fi

RUN /opt/conda/bin/python -c "import importlib.util, torch; assert importlib.util.find_spec('torch.sagemaker'), 'torch.sagemaker missing after SMP install'"

# Verify cuDNN resolves libcublasLt from the expected CUDA 12.4 stack.
RUN ldd -r /usr/lib/x86_64-linux-gnu/libcudnn_adv.so.9 2>/dev/null | grep -E 'cublasLt|not found' || true; \
    ldd -r /usr/lib/x86_64-linux-gnu/libcudnn_engines_precompiled.so.9 2>/dev/null | grep -E 'cublasLt|not found' || true

# Align NeMo 2.3 stack dependencies after SMP torch is installed
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/uv pip install --system --no-deps \
        megatron-core==0.12.3 \
        torchvision==0.20.1 \
        nemo-toolkit==2.3.0 \
        nvidia-modelopt==0.23.2 \
        nvidia-modelopt-core==0.23.2 \
    && /opt/conda/bin/uv pip install --system --no-deps --no-build-isolation mamba-ssm==2.2.6.post3

# Shim megatron-core async_utils for hyperpod_nemo_adapter (export DistributedAsyncCaller)
RUN /opt/conda/bin/python -c "from pathlib import Path; p=Path('/opt/conda/lib/python3.11/site-packages/megatron/core/dist_checkpointing/strategies/async_utils.py'); t=p.read_text(); marker='Shim: export DistributedAsyncCaller'; need=('DistributedAsyncCaller =' not in t and 'class DistributedAsyncCaller' not in t); shim='\\n\\n# Shim: export DistributedAsyncCaller\\ntry:\\n    DistributedAsyncCaller\\nexcept NameError:\\n    try:\\n        DistributedAsyncCaller = TemporalAsyncCaller\\n    except NameError:\\n        DistributedAsyncCaller = AsyncCaller\\n'; p.write_text(t+shim) if need else None"

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
    CUDNN_PATH=/usr \
    CUDNN_LIBRARY=/usr/lib/x86_64-linux-gnu \
    CUDNN_INCLUDE_DIR=/usr/include \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH \
    NVTE_FRAMEWORK=pytorch \
    MAX_JOBS=${BUILD_JOBS} \
    CMAKE_BUILD_PARALLEL_LEVEL=${BUILD_JOBS} \
    NVTE_BUILD_THREADS_PER_JOB=1 \
    /opt/conda/bin/uv pip install --system --no-build-isolation --no-deps \
        --extra-index-url ${TRANSFORMER_ENGINE_INDEX_URL} \
        "transformer_engine==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine_cu12==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine_torch==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine[jax]==${TRANSFORMER_ENGINE_VERSION}" \
        "transformer_engine[paddle]==${TRANSFORMER_ENGINE_VERSION}"

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/uv pip install --system --no-deps ${SMDDP_WHL_URL}


RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/bin/python -m pip install uv \
    && /opt/conda/bin/uv pip install --system \
        attrs \
        aiobotocore 
# Ensure psutil is fully installed (binary wheel with native extension)
RUN /opt/conda/bin/python -m pip install --force-reinstall --no-cache-dir --only-binary=:all: psutil==7.2.1 \
    && /opt/conda/bin/python -c "import psutil; assert getattr(psutil,'__file__',None), 'psutil missing __file__ (namespace package)'; assert hasattr(psutil,'virtual_memory'), 'psutil missing virtual_memory'; print('psutil OK:', psutil.__version__)"

# Patch torch.sagemaker TE version parsing (late layer to avoid full rebuild)
RUN /opt/conda/bin/python -c "from pathlib import Path; p=Path('/opt/conda/lib/python3.11/site-packages/torch/sagemaker/patches/patch_manager.py'); t=p.read_text(); \
old1='def get_loose_version(self, cur_TE_version_commit_id: str):\\n        \"\"\"\\n        Returns the loose TE version.\\n        \"\"\"\\n        version, commit_id = cur_TE_version_commit_id.split(\"+\")\\n        return version\\n'; \
new1='def get_loose_version(self, cur_TE_version_commit_id: str):\\n        \"\"\"\\n        Returns the loose TE version.\\n        \"\"\"\\n        if \"+\" in cur_TE_version_commit_id:\\n            version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n            return version\\n        return cur_TE_version_commit_id\\n'; \
old2='def get_loose_version(cur_TE_version_commit_id: str) -> str:\\n    version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n    return version\\n'; \
new2='def get_loose_version(cur_TE_version_commit_id: str) -> str:\\n    if \"+\" in cur_TE_version_commit_id:\\n        version, _ = cur_TE_version_commit_id.split(\"+\", maxsplit=1)\\n        return version\\n    return cur_TE_version_commit_id\\n'; \
cond=('return cur_TE_version_commit_id' in t); \
p.write_text(t.replace(old1, new1).replace(old2, new2)) if (old1 in t or old2 in t) else print('patch_manager.py already patched.') if cond else print('patch_manager.py format changed; no update applied.')"

# Shim torch.sagemaker async_utils DistributedAsyncCaller for megatron-core>=0.12 API
RUN /opt/conda/bin/python -c "from pathlib import Path; p=Path('/opt/conda/lib/python3.11/site-packages/torch/sagemaker/distributed/checkpoint/async_utils.py'); t=p.read_text(); marker='Shim: sm async_utils compat'; \
lines=['', '# Shim: sm async_utils compat', 'try:', '    from megatron.core.dist_checkpointing.strategies.async_utils import TemporalAsyncCaller as _TAC, AsyncRequest as _AR', '    def _init(self): _TAC.__init__(self)', '    def _schedule_async_call(self, async_req_or_fn, async_fn_args=None, async_fn_kwargs=None):', '        if isinstance(async_req_or_fn, _AR):', '            return _TAC.schedule_async_call(self, async_req_or_fn)', '        if async_fn_kwargs is None:', '            async_fn_kwargs = {}', '        return _TAC.schedule_async_call(self, _AR(async_req_or_fn, async_fn_args, [], async_fn_kwargs))', '    def _is_current_async_call_done(self, blocking=True, no_dist=False):', '        return _TAC.is_current_async_call_done(self, blocking, no_dist)', '    def _close(self):', '        return _TAC.close(self)', '    def _del(self):', '        return None', '    DistributedAsyncCaller.__init__ = _init', '    DistributedAsyncCaller.schedule_async_call = _schedule_async_call', '    DistributedAsyncCaller.is_current_async_call_done = _is_current_async_call_done', '    DistributedAsyncCaller.close = _close', '    DistributedAsyncCaller.__del__ = _del', '    DistributedAsyncCaller.__abstractmethods__ = frozenset()', 'except Exception:', '    pass']; \
shim='\\n'.join(lines); p.write_text(t+shim) if marker not in t else None"

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

# Temporary hotfix: ensure torchx/importlib_metadata dependency chain is satisfied.
RUN /opt/conda/bin/pip install --no-cache-dir zipp uvicorn pytz tiktoken

# Patch nemo_run API to expose factory/task and support for_task (late layer to minimize rebuilds)
RUN /opt/conda/bin/python -c 'from pathlib import Path; p=Path("/opt/conda/lib/python3.11/site-packages/nemo_run/__init__.py"); t=p.read_text(); shim="""# Compatibility shims for NeMo LLM expecting nemo_run.factory/task\n\ndef factory(fn=None, **kwargs):\n    if \"for_task\" in kwargs and \"namespace\" not in kwargs:\n        kwargs[\"namespace\"] = kwargs.pop(\"for_task\")\n    else:\n        kwargs.pop(\"for_task\", None)\n    def wrap(f):\n        if not hasattr(f, \"__auto_config__\"):\n            setattr(f, \"__auto_config__\", True)\n        return cli.factory(f, **kwargs)\n    return wrap if fn is None else wrap(fn)\n\ndef task(*args, **kwargs):\n    return cli.entrypoint(*args, **kwargs)\n\ntry:\n    __all__.extend([\"factory\", \"task\"])\nexcept Exception:\n    pass\n"""; p.write_text(t + "\n\n" + shim) if "Compatibility shims for NeMo LLM" not in t else None'

WORKDIR /workspace
