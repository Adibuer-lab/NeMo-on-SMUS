# syntax=__DOCKERFILE_FRONTEND__
ARG LLMFT_SCRIPTS_IMAGE
FROM ${LLMFT_SCRIPTS_IMAGE} as llmft_scripts

FROM nvcr.io/nvidia/nemo:25.11

# Build arguments for version control
ARG GDRCOPY_VERSION=v2.4.1
# Match base image libfabric 1.22.0amzn5.0 (EFA installer 1.38.1)
ARG EFA_INSTALLER_VERSION=1.38.1
ARG AWS_OFI_NCCL_VERSION=v1.17.2
ARG NCCL_VERSION=v2.27.7
ARG NCCL_TESTS_VERSION=v2.13.10
ARG OPEN_MPI_PATH=/opt/amazon/openmpi
ARG BUILD_JOBS=36
ARG ADAPTER_CACHE_BUST=32

ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PIP_CACHE_DIR=/root/.cache/pip \
    UV_CACHE_DIR=/root/.cache/uv \
    UV_CONCURRENT_BUILDS=${BUILD_JOBS} \
    UV_CONCURRENT_INSTALLS=${BUILD_JOBS} \
    UV_CONCURRENT_DOWNLOADS=32

# Import HyperPod runtime scripts from LLMFT image
COPY --from=llmft_scripts /opt/bin /opt/bin

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
    DEBIAN_FRONTEND=noninteractive apt install -y --allow-unauthenticated \
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
    && apt autoremove -y

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
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

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

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat/:$LIBRARY_PATH
ENV CPATH=/opt/gdrcopy/include:$CPATH
ENV PATH=/opt/gdrcopy/bin:$PATH

######################
# Install EFA installer
######################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -e; \
    . /etc/os-release; \
    codename="${VERSION_CODENAME:-}"; \
    if [ -z "$codename" ]; then \
        codename="$(lsb_release -cs 2>/dev/null || true)"; \
    fi; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i -E "s/^Suites:.*/Suites: ${codename} ${codename}-updates ${codename}-security/" /etc/apt/sources.list.d/ubuntu.sources; \
        sed -i -E "s/^Components:.*/Components: main restricted universe multiverse/" /etc/apt/sources.list.d/ubuntu.sources; \
        rm -f /etc/apt/sources.list; \
    elif [ -n "$codename" ]; then \
        echo "deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse" > /etc/apt/sources.list; \
        echo "deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse" >> /etc/apt/sources.list; \
        echo "deb http://archive.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse" >> /etc/apt/sources.list; \
    fi; \
    apt-get update -y; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        software-properties-common \
        python3-venv \
        udev \
        dmidecode \
        ethtool \
        iproute2 \
        pciutils \
        tcl \
        environment-modules; \
    if [ "$codename" = "noble" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            libevent-core-2.1-7t64 \
            libevent-pthreads-2.1-7t64; \
    fi; \
    apt-get autoremove -y

RUN apt-get update -y \
    && cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g --skip-kmod --skip-limit-conf --no-verify \
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
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m venv --system-site-packages /opt/venv \
    && /opt/venv/bin/python -m pip install --upgrade pip \
    && /opt/venv/bin/python -m pip install --upgrade --force-reinstall uv

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    /opt/venv/bin/python -m uv pip install \
    # Only install packages not already present in base image to avoid version skew
    sagemaker \
    python-etcd \
    hyperpod-elastic-agent==1.1.0 \
    nv-one-logger-core \
    nv-one-logger-training-telemetry \
    nv-one-logger-pytorch-lightning-integration\
    nv-one-logger-otel 

# Ensure venv doesn't shadow base image Torch/Triton (use system Torch + TE)
RUN /opt/venv/bin/pip uninstall -y torch torchvision torchaudio triton || true

# Remove CUDA 12 runtime wheels pulled in by numba-cuda to avoid mixed CUDA runtimes
# (uninstall from both venv and system site-packages since venv uses --system-site-packages)
RUN /opt/venv/bin/pip uninstall -y numba-cuda nvidia-cuda-runtime-cu12 nvidia-cuda-nvrtc-cu12 nvidia-cuda-cupti-cu12 || true \
    && /usr/bin/python3 -m pip uninstall -y numba-cuda nvidia-cuda-runtime-cu12 nvidia-cuda-nvrtc-cu12 nvidia-cuda-cupti-cu12 || true

######################
# Install SageMaker HyperPod training adapter for NeMo from source
######################
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    echo "Cache bust value: ${ADAPTER_CACHE_BUST}" \
    && git clone https://github.com/Adibuer-lab/sagemaker-hyperpod-training-adapter-for-nemo.git /opt/hyperpod-adapter \
    && cd /opt/hyperpod-adapter \
    && /opt/venv/bin/python -m uv pip install --no-deps ".[all]"



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
