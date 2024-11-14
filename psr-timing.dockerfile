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
    wget git \   
    ca-certificates openssh-server \
    build-essential cmake \
    libfftw3-bin libfftw3-dev \
    libgsl-dev libgslcblas0 gsl-bin \
    libblas-dev liblapack-dev \
    pgplot5 xauth xorg \
    libcfitsio-bin libcfitsio-dev \
    perl libpcre2-dev pcre2-utils libpcre3 libpcre3-dev locales \
    libpng-dev libpnglite-dev \
    gfortran gcc g++ \
    tcsh csh \
    autoconf autotools-dev automake autogen libtool libltdl-dev \
    libx11-dev tk-dev \
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
RUN git clone https://git.code.sf.net/p/tempo/tempo && \
    git clone https://bitbucket.org/psrsoft/tempo2.git && \
    git clone https://github.com/ipta/pulsar-clock-corrections.git && \
    wget "https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.tar.gz" && \
    wget "https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-${CALCEPH_VER}.tar.gz"

## INSTALL ##
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

########
# PINT #
########
RUN pip install --prefix=${PSRHOME} git+https://github.com/nanograv/PINT.git
#RUN ls -R ${PSRHOME} | grep ":$" | sed -e 's/:$//' -e 's/[^-][^\/]*\//--/g' -e 's/^/   /' -e 's/-/|/'
ENV PATH="${PATH}:${PSRHOME}/local/bin"
ENV PYTHONPATH="${PYTHONPATH}:${PSRHOME}/local/lib/python3.12/dist-packages"

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
    sed -i "s;${TEMPO_DIR};${TEMPO};g" ${TEMPO}/tempo.cfg && \
    cd ${TEMPO_DIR}/src && \
    make matrix && \
    cp matrix ${TEMPO}/bin/ && \
    cd ${TEMPO_DIR}/util/lk && \
    gfortran -o lk lk.f && \
    cp lk ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/dmx/* ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/dmxparse/* ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/dmx_ranges/* ${TEMPO}/bin/ && \
    chmod +x ${TEMPO}/bin/DMX_ranges2.py && \
    cp ${TEMPO_DIR}/util/dmx_broaden/* ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/cull/cull.pl ${TEMPO}/bin/cull && \
    cp ${TEMPO_DIR}/util/extract/extract.pl ${TEMPO}/bin/extract && \
    cp ${TEMPO_DIR}/util/obswgt/obswgt.pl ${TEMPO}//bin/obswg && \   
    cd ${TEMPO_DIR}/util/print_resid && \
    make -j && \
    cp print_resid ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/res_avg/* ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/wgttpo/wgttpo.pl ${TEMPO}/bin/wgttpo && \
    cp ${TEMPO_DIR}/util/wgttpo/wgttpo_emin.pl ${TEMPO}/bin/wgttpo_emin && \
    cp ${TEMPO_DIR}/util/wgttpo/wgttpo_equad.pl ${TEMPO}/bin/wgttpo_equad && \
    cp ${TEMPO_DIR}/util/compare_tempo/compare_tempo ${TEMPO}/bin/ && \
    cp ${TEMPO_DIR}/util/pubpar/pubpar.py ${TEMPO}/bin/ && \
    chmod +x ${TEMPO}/bin/pubpar.py && \
    cp ${TEMPO_DIR}/util/center_epoch/center_epoch.py ${TEMPO}/bin/ && \
    cd ${TEMPO_DIR}/util/avtime && \
    gfortran -o avtime avtime.f && \
    cp avtime ${TEMPO}/bin/ && \
    cd ${TEMPO_DIR}/util/non_tempo && \
    cp dt mjd aolst ${TEMPO}/bin/ && \
    cd ${TEMPO_DIR}

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


WORKDIR ${PSRHOME}
