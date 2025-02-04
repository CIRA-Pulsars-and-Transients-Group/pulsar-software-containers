# syntax=docker/dockerfile:1
FROM ubuntu:24.04

# Set system config variables
ARG DEBIAN_FRONTEND=noninteractive
ENV OSTYPE=linux

# Setup base installation path
ENV PSRHOME=/software
ENV PATH="${PATH}:${PSRHOME}/bin"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PSRHOME}/lib"
ENV C_INCLUDE_PATH="${C_INCLUDE_PATH}:${PSRHOME}/include"

# System package installs
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git wget \   
    ca-certificates openssh-server \
    build-essential cmake \
    autoconf autotools-dev automake autogen libtool libltdl-dev pkg-config \
    libfftw3-bin libfftw3-dev \
    libgsl-dev libgslcblas0 gsl-bin \
    libblas-dev liblapack-dev \
    libarmadillo-dev libarmadillo12 \
    pgplot5 xauth xorg \
    libcfitsio-bin libcfitsio-dev \
    perl libpcre2-dev pcre2-utils libpcre3 libpcre3-dev locales \
    libpng-dev libpnglite-dev \
    gfortran gcc g++ \
    tcsh csh \
    libx11-dev tk-dev \
    swig \
    python3-dev python3-numpy python3-pip python3-venv python3-tk && \
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

# Make Python 3.12 the default version
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.12 1 && \
    rm /usr/lib/python3.12/EXTERNALLY-MANAGED && \
    python -V && \
    python3 -V

# Install required systems Python packages
RUN pip install numpy && \
    pip install scipy && \
    pip install matplotlib && \
    pip install ipython


# Download software repositories
WORKDIR ${PSRHOME}
ARG CALCEPH_VER="4.0.1"
RUN git clone https://bitbucket.org/psrsoft/tempo2.git && \
    git clone https://github.com/ipta/pulsar-clock-corrections.git && \
    git clone git://git.code.sf.net/p/psrchive/code psrchive && \
    git clone git://git.code.sf.net/p/dspsr/code dspsr && \
    git clone https://github.com/weltevrede/psrsalsa.git && \
    wget "https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.tar.gz" && \
    wget "https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-${CALCEPH_VER}.tar.gz"

### INSTALL ###

##########
# PSRCAT #
##########
ENV PSRCAT_FILE=${PSRHOME}/share/psrcat.db
ENV PSRCAT_DIR=${PSRHOME}/psrcat

RUN tar -xvf psrcat_pkg.tar.gz && \
    mv psrcat_tar psrcat && \
    rm -f psrcat_pkg.tar.gz && \
    mkdir -p ${PSRHOME}/bin && \
    mkdir -p ${PSRHOME}/share
WORKDIR ${PSRCAT_DIR}
RUN tcsh makeit && \
    cp psrcat ${PSRHOME}/bin && \
    cp *.db ${PSRHOME}/share

###########
# CALCEPH #
###########
ENV CALCEPH_DIR="${PSRHOME}/calceph-${CALCEPH_VER}"
ENV CALCEPH="${CALCEPH_DIR}/install"
ENV PATH="${PATH}:${CALCEPH}/bin"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${CALCEPH}/lib"
ENV C_INCLUDE_PATH="${C_INCLUDE_PATH}:${CALCEPH}/include"

WORKDIR ${PSRHOME}
RUN tar -xvf calceph-${CALCEPH_VER}.tar.gz && \
    rm -f calceph-${CALCEPH_VER}.tar.gz
WORKDIR ${CALCEPH_DIR}
RUN mkdir -p ${CALCEPH_DIR}/build && cd ${CALCEPH_DIR}/build && \
    CC=gcc CXX=g++ FC=gfortran \
    FFLAGS="$FFLAGS -O3 -march=znver3" \
    CFLAGS="$CFLAGS -O3 -march=znver3" \
    CXXFLAGS="$CXXFLAGS -O3 -march=znver3" \
    cmake -DCMAKE_INSTALL_PREFIX=${CALCEPH} -DBUILD_SHARED_LIBS=ON .. && \
    cmake --build . --target all && \
    cmake --build . --target test && \
    cmake --build . --target install && \
    cmake --build . --target clean

##########
# TEMPO2 #
##########
ENV TEMPO2_DIR="${PSRHOME}/tempo2"
ENV TEMPO2="${TEMPO2_DIR}/install"
ENV TEMPO2_ALIAS="tempo"
ENV PATH="${PATH}:${TEMPO2}/bin"
ENV C_INCLUDE_PATH="${C_INCLUDE_PATH}:${TEMPO2}/include"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${TEMPO2}/lib"

WORKDIR ${TEMPO2_DIR}
RUN ./bootstrap && \
    cp -r T2runtime/ ${TEMPO2}/ && \
    CC=gcc CXX=g++ FC=gfortran F77=gfortran ./configure --prefix=${TEMPO2} \
    --with-x --x-libraries=/usr/lib/x86_64-linux-gnu \
    --with-fftw3-dir=/usr --with-calceph=${CALCEPH} \
    --enable-shared --enable-static --with-pic \
    FFLAGS="$FFLAGS -O3 -march=znver3 -I${CALCEPH}/include" \
    CFLAGS="$CFLAGS -O3 -march=znver3 -I${PGPLOT_DIR}/include -I${CALCEPH}/include" \
    CXXFLAGS="$CXXFLAGS -O3 -march=znver3 -I${PGPLOT_DIR}/include -I${CALCEPH}/include" \
    LDFLAGS="$LDFLAGS -L${PGPLOT_DIR}/lib -lpgplot -lcpgplot -L${CALCEPH}/lib -lcalceph"&& \
    make -j 8 && \
    make -j 8 plugins && \
    make install && \
    make plugins-install && \
    make clean && make plugins-clean

############################
# Update clock corrections #
############################
ENV CLK_CORR_DIR="${PSRHOME}/pulsar-clock-corrections"
WORKDIR ${CLK_CORR_DIR}
RUN pip install --prefix=${PSRHOME} -r requirements.txt
RUN python download-clock-corrections.py

############
# SPLINTER #
############
WORKDIR ${PSRHOME}
RUN git clone https://github.com/bgrimstad/splinter.git
RUN cd splinter && git pull && git checkout develop && \
    mkdir -p build && cd build && \
    cmake .. && \
    make -j 8 && \
    make install && \
    make clean && \
    ldconfig 

############
# PSRSALSA #
############
ENV PSRSALSA_DIR="${PSRHOME}/psrsalsa"
ENV PATH="${PATH}:${PSRSALSA_DIR}/bin"

WORKDIR ${PSRSALSA_DIR}
RUN cp Makefile Makefile.bak
ADD Makefile.psrsalsa Makefile
RUN make -j 8 && \
    ls ${PSRSALSA_DIR}/bin

############
# PSRCHIVE #
############
ENV PSRCHIVE_DIR="${PSRHOME}/psrchive"
ENV PATH="${PATH}:${PSRHOME}/bin"
ENV C_INCLUDE_PATH="${C_INCLUDE_PATH}:${PSRHOME}/include"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PSRHOME}/lib"
ENV PYTHONPATH="${PYTHONPATH}:${PSRHOME}/lib/python3.12/site-packages"
ENV PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${PSRHOME}/lib/pkgconfig"
ENV PSRCHIVE_CONFIG="${PSRHOME}/share/psrchive.config"

WORKDIR ${PSRCHIVE_DIR}
RUN ./bootstrap && \
    ./configure --prefix=${PSRHOME} --with-x --x-libraries=/usr/lib/x86_64-linux-gnu --enable-shared --enable-static \
    CC=gcc CXX=g++ F77=gfortran PYTHON=$(which python) \
    FFLAGS="$FFLAGS -O3 -march=znver3 -I/usr/local/include/" \
    CFLAGS="$CFLAGS -O3 -march=znver3 -I/usr/local/include/ -I${PGPLOT_DIR}/include/ -L${PGPLOT_DIR}/lib/" \
    CXXFLAGS="$CXXFLAGS -O3 -march=znver3 -I/usr/local/include -I${PGPLOT_DIR}/include/ -L${PGPLOT_DIR}/lib/" \
    LDFLAGS="-L${PGPLOT_DIR}/lib/" && \
    make -j 8 && \
    make install && \
    make clean && \
    ldconfig

RUN mkdir -p ${PSRHOME}/share && \
    ${PSRHOME}/bin/psrchive_config > ${PSRCHIVE_CONFIG} && \
    sed -i 's/# Dispersion::barycentric_correction = 0/Dispersion::barycentric_correction = 1/' ${PSRCHIVE_CONFIG} && \
    sed -i 's/# WeightedFrequency::round_to_kHz = 1/WeightedFrequency::round_to_kHz = 0/' ${PSRCHIVE_CONFIG} && \
    sed -i 's/# Predictor::default = polyco/Predictor::default = tempo2/' ${PSRCHIVE_CONFIG} && \
    sed -i 's/# Predictor::policy = ephem/Predictor::policy = default/' ${PSRCHIVE_CONFIG}

#########
# DSPSR #
#########
ENV DSPSR_DIR="${PSRHOME}/dspsr"

WORKDIR ${DSPSR_DIR}
#RUN swig -version && echo "${PKG_CONFIG_PATH}" && ls /software/lib/pkgconfig && echo "$(pkg-config --libs psrchive)" && echo "-I${PSRHOME}/include -I${PSRHOME}/include/epsic"
RUN ./bootstrap && \
    echo "apsr bpsr cpsr cpsr2 gmrt sigproc fits vdif kat lwa uwb spigot guppi" > backends.list && \
    ./configure --prefix=${PSRHOME} \
    PSRCHIVE_CFLAGS="$(psrchive --cflags)" \
    PSRCHIVE_LIBS="$(psrchive --libs)" \
    CC=gcc CXX=g++ F77=gfortran FC=gfortran \
    FFLAGS="$FFLAGS -O3 -march=znver3 -I/usr/local/include -I${PGPLOT_DIR}/include -I${PSRHOME}/include -I${PSRHOME}/include/epsic" \
    CFLAGS="$CFLAGS -O3 -march=znver3 -I/usr/local/include -I${PGPLOT_DIR}/include -I${PSRHOME}/include -I${PSRHOME}/include/epsic" \
    CXXFLAGS="$CXXFLAGS -O3 -march=znver3 -I/usr/local/include -I${PGPLOT_DIR}/include -I${PSRHOME}/include -I${PSRHOME}/include/epsic" && \
    make -j 8 && \
    make install && \
    make clean

####################
# PulsePortraiture #
####################
WORKDIR ${PSRHOME}
ENV PATH="${PATH}:${PSRHOME}/local/bin"
ENV PYTHONPATH="${PYTHONPATH}:${PSRHOME}/local/lib/python3.12/dist-packages"
RUN pip install --prefix=${PSRHOME} --no-cache-dir -U lmfit PyWavelets && \
    pip install --prefix=${PSRHOME} git+https://github.com/pennucci/PulsePortraiture.git@py3

########
# CLFD #
########
#RUN git clone https://github.com/bwmeyers/clfd.git clfd
#WORKDIR clfd
RUN pip install --prefix=${PSRHOME} clfd


WORKDIR ${PSRHOME}
