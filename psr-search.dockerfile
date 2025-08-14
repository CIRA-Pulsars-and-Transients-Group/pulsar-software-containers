# syntax=docker/dockerfile:1
FROM ubuntu:24.04

# Set system config variables
ARG DEBIAN_FRONTEND=noninteractive
ENV OSTYPE=linux

# Setup base installation path
ENV PSRHOME=/software
ENV PATH="${PATH}:${PSRHOME}/bin"
ENV PATH="${PATH}:${PSRHOME}/local/bin"
ENV PYTHONPATH="${PYTHONPATH}:${PSRHOME}/local/lib/python3.12/dist-packages"

RUN apt-get update &&\
    apt-get install -y --no-install-recommends \
    git wget \   
    ca-certificates openssh-server \
    build-essential \
    perl libpcre2-dev pcre2-utils libpcre3 libpcre3-dev locales \
    libfftw3-bin libfftw3-dev \
    libblas-dev liblapack-dev \
    pgplot5 xauth xorg \
    libglib2.0-dev \
    libgsl-dev libgslcblas0 gsl-bin \
    libcfitsio-bin libcfitsio-dev \
    libpng-dev libpnglite-dev \
    gfortran gcc g++ swig \
    tcsh csh \
    autoconf autotools-dev automake autogen libtool libltdl-dev pkg-config \
    libx11-dev tk-dev \
    python3-dev python3-pip python3-venv python3-tk \
    vim less \
    rsync \
    latex2html && \
    rm -rf /var/lib/apt/lists/* && apt-get -y clean

# Setup PGPLOT environment
ENV PGPLOT_DIR=/usr
ENV PGPLOT_FONT="${PGPLOT_DIR}/lib/pgplot5/grfont.dat"
ENV PGPLOT_INCLUDES="${PGPLOT_DIR}/include"
ENV PGPLOT_BACKGROUND=white
ENV PGPLOT_FOREGROUND=black
ENV PGPLOT_DEV=/xs
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PGPLOT_DIR}/lib"
ENV C_INCLUDE_PATH="${C_INCLUDE_PATH}:${PGPLOT_DIR}/include"

# Setup locale information
RUN localedef -i en_AU -c -f UTF-8 -A /usr/share/locale/locale.alias en_AU.UTF-8
ENV LANG=en_AU.UTF8
ENV LC_ALL=en_AU.UTF8
ENV LANGUAGE=en_AU.UTF8

# Make Python 3.12 the default version and get build packages
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.12 1 && \
    rm /usr/lib/python3.12/EXTERNALLY-MANAGED && \
    python -V && \
    python3 -V
RUN pip install meson meson-python ninja

# Download software repositories
WORKDIR ${PSRHOME}
RUN git clone https://git.code.sf.net/p/tempo/tempo tempo && \
    git clone https://github.com/scottransom/presto.git presto && \
    git clone https://github.com/v-morello/riptide.git riptide && \
    wget "https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.tar.gz"

### INSTALL ###

##########
# PSRCAT #
##########
ENV PSRCAT_FILE="${PSRHOME}/share/psrcat.db"
ENV PSRCAT_DIR="${PSRHOME}/psrcat"

RUN tar -xvf psrcat_pkg.tar.gz && \
    mv psrcat_tar psrcat && \
    rm -f psrcat_pkg.tar.gz && \
    mkdir -p ${PSRHOME}/bin && \
    mkdir -p ${PSRHOME}/share
WORKDIR ${PSRCAT_DIR}
RUN sh makeit && \
    cp psrcat ${PSRHOME}/bin && \
    cp *.db ${PSRHOME}/share

#########
# TEMPO #
#########
ENV TEMPO_DIR="${PSRHOME}/tempo"
ENV TEMPO="${PSRHOME}/tempo/install"
ENV PATH="${PATH}:${TEMPO}/bin"

WORKDIR ${TEMPO_DIR}
RUN ./prepare && \
    ./configure --prefix=${TEMPO} FC=gfortran F77=gfortran FFLAGS="$FFLAGS -O3 -march=znver3" && \
    make -j && \
    make install && \
    make clean && \
    cp -r clock/ ephem/ tzpar/ obsys.dat tempo.cfg tempo.hlp ${TEMPO} && \
    sed -i "s;${TEMPO_DIR};${TEMPO};g" ${TEMPO}/tempo.cfg

##########
# PRESTO #
##########
WORKDIR ${PSRHOME}/presto

ENV PRESTO="${PSRHOME}/presto"
ENV PATH="${PRESTO}/installation/bin:${PATH}"
ENV LIBRARY_PATH="${PRESTO}/installation/lib/x86_64-linux-gnu:${LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="${PRESTO}/installation/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

RUN CFLAGS="$CFLAGS -march=znver3 -O3" meson setup build --prefix=${PRESTO}/installation && \
    python check_meson_build.py
RUN CFLAGS="$CFLAGS -march=znver3 -O3" meson compile -C build && \
    meson install -C build

WORKDIR ${PRESTO}/python
RUN pip install --config-settings=builddir=build .

# Ensure scripts in presto/examplescripts are executable
RUN chmod +x ${PRESTO}/examplescripts/*.py
# Fix the shebangs
RUN cd ${PRESTO}/examplescripts && \
    sed -i '1s;^;#!/usr/bin/env python\n;' ACCEL_sift.py concatdata.py dedisp.py ffdot_example.py jerk_example.py pdm2raw.py show_zresp.py testcorr.py && \
    sed -i '1s;.*;#!/usr/bin/env python;' short_analysis_simple.py ppdot_plane_plot.py full_analysis.py && \
    cd -

# In principle you can generate wisdom here, but it's not that useful
# for machines with different architectures than the one on which the
# docker container was built.
#WORKDIR ${PRESTO}/src
#RUN ${PRESTO}/build/src/makewisdom
#RUN mv ${PRESTO}/src/fftw_wisdom.txt ${PRESTO}/lib

###########
# RIPTIDE #
###########
WORKDIR ${PSRHOME}/riptide
RUN sed -i "s:pip install -e:pip install --prefix=$PSRHOME:" Makefile && \
    make clean && \
    make install && \
    make clean

##############
# sigpyproc3 #
############## 
WORKDIR ${PSRHOME}
RUN pip install --prefix=${PSRHOME} git+https://github.com/FRBs/sigpyproc3


# Fix Singularity environment setup
# Singularity: will execute scripts in /.singularity.d/env/ at startup (and ignore those in /etc/profile.d/).
#              Standard naming of "environment" scripts is 9X-environment.sh
RUN mkdir -p /.singularity.d/env/
RUN echo "export OSTYPE=$OSTYPE" >> /.singularity.d/env/91-environment.sh && \
    echo "export LANG=$LANG LC_ALL=$LC_ALL LANGUAGE=$LANGUAGE" >> /.singularity.d/env/91-environment.sh && \
    echo "export LIBRARY_PATH=$LIBRARY_PATH" >> /.singularity.d/env/91-environment.sh && \
    echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> /.singularity.d/env/91-environment.sh && \
    echo "export C_INCLUDE_PATH=$C_INCLUDE_PATH" >> /.singularity.d/env/91-environment.sh && \
    echo "export PATH=$PATH" >> /.singularity.d/env/91-environment.sh && \
    echo "export PYTHONPATH=$PYTHONPATH" >> /.singularity.d/env/91-environment.sh && \
    echo "export PSRHOME=$PSRHOME" >> /.singularity.d/env/91-environment.sh && \
    echo "export PSRCAT_DIR=$PSRCAT_DIR PSRCAT_FILE=$PSRCAT_FILE" >> /.singularity.d/env/91-environment.sh && \
    echo "export TEMPO=$TEMPO TEMPO_DIR=$TEMPO_DIR" >> /.singularity.d/env/91-environment.sh && \
    echo "export PRESTO=$PRESTO" >> /.singularity.d/env/91-environment.sh && \
    echo "export PGPLOT_DIR=$PGPLOT_DIR PGPLOT_INCLUDES=$PGPLOT_INCLUDES PGPLOT_FONT=$PGPLOT_FONT" >> /.singularity.d/env/91-environment.sh && \
    echo "export PGPLOT_DEV=$PGPLOT_DEV PGPLOT_BACKGROUND=$PGPLOT_BACKGROUND PGPLOT_FOREGROUND=$PGPLOT_FOREGROUND" >> /.singularity.d/env/91-environment.sh

# Copy the recipe into the docker recipes directory
RUN mkdir -p /opt/docker-recipes/
COPY psr-search.dockerfile /opt/docker-recipes/

WORKDIR ${PSRHOME}
