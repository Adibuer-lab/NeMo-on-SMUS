FROM nvcr.io/nvidia/nemo:25.04

# Build arguments for version control
# NeMo 25.04 includes: PyTorch 2.7.0, CUDA 12.9, NeMo 2.3.0, Megatron Core 0.12.0
ARG GDRCOPY_VERSION=v2.4.1
ARG EFA_INSTALLER_VERSION=1.45.1
ARG AWS_OFI_NCCL_VERSION=v1.17.2
ARG NCCL_VERSION=v2.27.7
ARG NCCL_TESTS_VERSION=v2.13.10
ARG TRANSFORMERS_VERSION=4.48.1
ARG OPEN_MPI_PATH=/opt/amazon/openmpi

######################
# Update and remove IB libverbs
######################
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get remove -y --allow-change-held-packages \
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
RUN DEBIAN_FRONTEND=noninteractive apt install -y --allow-unauthenticated \
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
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        check pkg-config

######################
# Install NVIDIA GDRCopy
######################
RUN git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make prefix=/opt/gdrcopy install \
    && rm -rf /tmp/gdrcopy

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat:$LD_LIBRARY_PATH
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
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libhwloc-dev

SHELL ["/bin/bash", "-c"]
RUN curl -OL https://github.com/aws/aws-ofi-nccl/releases/download/${AWS_OFI_NCCL_VERSION}/aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && tar -xf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v}.tar.gz \
    && cd aws-ofi-nccl-${AWS_OFI_NCCL_VERSION//v} \
    && ./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws \
    && make -j $(nproc) \
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
RUN pip3 install --no-cache-dir \
    awscli==1.44.7 \
    boto3==1.42.17 \
    sagemaker==3.3.0 \
    pynvml \
    wandb \
    transformers==${TRANSFORMERS_VERSION} \
    sentencepiece \
    python-etcd \
    nemo-run==0.4.0 \
    nemoguardrails \
    hyperpod-elastic-agent==1.1.0 \
    skypilot-nightly[kubernetes]

######################
# Install SageMaker HyperPod training adapter for NeMo from source
######################
RUN git clone https://github.com/Adibuer-lab/sagemaker-hyperpod-training-adapter-for-nemo.git /opt/hyperpod-adapter \
    && cd /opt/hyperpod-adapter \
    && pip3 install --no-cache-dir ".[all]"

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
