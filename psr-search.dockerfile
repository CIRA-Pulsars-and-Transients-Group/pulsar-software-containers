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
    ca-certificates \
    build-essential \
    perl libpcre2-dev pcre2-utils libpcre3 libpcre3-dev locales \
    libfftw3-bin libfftw3-dev \
    libblas-dev liblapack-dev \
    pgplot5 xauth xorg \
    libglib2.0-dev \
    libgsl-dev gsl-bin \
    libcfitsio-bin libcfitsio-dev \
    libpng-dev libpnglite-dev \
    gfortran gcc g++ swig \
    tcsh csh \
    autoconf autotools-dev automake autogen libtool libltdl-dev pkg-config \
    libx11-dev tk-dev \
    python3-dev python3-numpy python3-pip python3-venv python3-tk \
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
    git clone https://github.com/ipta/pulsar-clock-corrections.git && \
    git clone https://github.com/scottransom/presto.git presto && \
    git clone https://github.com/v-morello/riptide.git riptide

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
    cd ${TEMPO_DIR}/util/ut1 && \
    gcc -o predict_ut1 predict_ut1.c $(gsl-config --libs) && \
    cp predict_ut1 check.ut1 do.iers.ut1 do.iers.ut1.new get_ut1 get_ut1_new make_ut1 ${TEMPO}/bin/ && \
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

############################
# Update clock corrections #
############################
WORKDIR ${PSRHOME}/pulsar-clock-corrections
RUN pip install --prefix=${PSRHOME} -r requirements.txt
RUN python download-clock-corrections.py

##########
# PRESTO #
##########
WORKDIR ${PSRHOME}/presto

ENV PRESTO="${PSRHOME}/presto"
ENV PATH="${PRESTO}/installation/bin:${PATH}"
ENV LIBRARY_PATH=${PRESTO}/installation/lib/x86_64-linux-gnu:${LIBRARY_PATH}
ENV LD_LIBRARY_PATH=${PRESTO}/installation/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}

RUN CFLAGS="$CFLAGS -march=znver3 -O3" meson setup build --prefix=${PRESTO}/installation && \
    python check_meson_build.py
RUN CFLAGS="$CFLAGS -march=znver3 -O3" meson compile -C build && \
    meson install -C build

WORKDIR ${PRESTO}/python
RUN pip install --config-settings=builddir=build .

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

RUN ls ${PSRHOME}

WORKDIR ${PSRHOME}





