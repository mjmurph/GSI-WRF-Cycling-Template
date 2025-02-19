#!/bin/ksh
#####################################################
# Description
#####################################################
# This driver script is a major fork and rewrite of the standard GSI ksh
# driver script for 3DVAR used in the GSI tutorial
# https://dtcenter.ucar.edu/com-GSI/users/tutorial/online_tutorial/index_v3.7.php
#
# The purpose of this fork is to work in a Rocoto-based
# Observation-Analysis-Forecast cycle with WRF for data denial 
# experiments. Naming conventions in this script have been smoothed
# to match a companion major fork of the wrf.ksh
# WRF driver script of Christopher Harrop.
#
# One should write machine specific options for the GSI environment
# in a GSI_constants.ksh script to be sourced in the below.  Variables
# aliases in this script are based on conventions defined in the 
# companion GSI_constants.ksh with this driver.
#
# SEE THE README FOR FURTHER INFORMATION
#
#####################################################
# License Statement:
#####################################################
# Copyright 2022 Colin Grudzien, cgrudzien@ucsd.edu
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
#
#####################################################
# Preamble
#####################################################
# Options below are hard-coded based on the type of experiment
# (i.e., these not expected to change within DA cycles).
#
# bk_core     = which WRF core is used as background (NMM or ARW or NMMB)
# bkcv_option = which background error covariance and parameter will be used 
#              (GLOBAL or NAM)
#
# if_clean    = clean  : delete temporal files in working directory (default)
#               no     : leave running directory as is (this is for debug only)
# BYTE_ORDER  = Big_Endian or Little_Endian
#
#####################################################

# uncomment to run verbose for debugging / testing
set -x

bk_core=ARW
bkcv_option=NAM
if_clean=clean
BYTE_ORDER=Big_Endian

#####################################################
# Read in GSI constants for local environment 
#####################################################

if [ ! -x "${CONSTANT}" ]; then
  ${ECHO} "ERROR: \$CONSTANT does not exist or is not executable!"
  exit 1
fi

. ${CONSTANT}

#####################################################
# Make checks for DA method settings
#####################################################
# Options below are defined in cycling.xml
#
# IF_SATRAD   = Yes   : GSI uses conventional data from prepbufr,
#                       satellite radiances, gpsro and radar data 
#               No    : GSI uses conventional data alone
#
# IF_OBSERVER = Yes   : only used as observation operator for EnKF
# NO_MEMBER   = INT   : number of ensemble members must be specified
#                       when IF_OBSERVER = yes above          
# IF_HYBRID   = Yes   : Run GSI as 3D/4D EnVar
# IF_4DENVAR  = Yes   : Run GSI as 4D EnVar 
#                       NOTE set `IF_HYBRID=Yes` first
# IF_NEMSIO   = Yes   : The GFS background files are in NEMSIO format
# IF_ONEOB    = Yes   : Do single observation test
#
#####################################################

if [[ ${IF_SATRAD} != Yes && ${IF_SATRAD} != No ]]; then
  ${ECHO} "ERROR: \$IF_SATRAD must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [[ ${IF_OBSERVER} != Yes && ${IF_OBSERVER} != No ]]; then
  ${ECHO} "ERROR: \$IF_OBSERVER must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [ ${IF_OBSERVER} = Yes ]; then
  if [ -z "${NO_MEMBER}" ]; then
    ${ECHO} "ERROR: \$NO_MEMBER must be defined as the ensemble size \$IF_OBSERVER = True"
    exit 1
  fi
fi

if [[ ${IF_HYBRID} != Yes && ${IF_HYBRID} != No ]]; then
  ${ECHO} "ERROR: \$IF_HYBRID must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [[ ${IF_4DENVAR} != Yes && ${IF_4DENVAR} != No ]]; then
  ${ECHO} "ERROR: \$IF_4DENVAR must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [[ ${IF_NEMSIO} != Yes && ${IF_NEMSIO} != No ]]; then
  ${ECHO} "ERROR: \$IF_NEMSIO must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [[ ${IF_ONEOB} != Yes && ${IF_ONEOB} != No ]]; then
  ${ECHO} "ERROR: \$IF_ONEOB must equal 'Yes' or 'No' case sensitive!"
  exit 1
fi

if [ ${IF_ONEOB} = Yes ]; then
  if_oneobtest='.true.'
else
  if_oneobtest='.false.'
fi

#####################################################
# Define GSI workflow dependencies
#####################################################
# Below variables are defined in cycling.xml workflow variables
#
# ANAL_TIME      = analysis time YYYYMMDDHH*
# GSI_ROOT       = directory for clean GSI build
# CRTM_VERSION   = version number of CRTM to specify path to binaries
# INPUT_DATAROOT = analysis time named directory for input data, containing
#                  subdirectories obs, bkg, gfsens, wrfprd, wpsprd
# MPIRUN         = MPI Command to execute GSI
#
# Below variables are derived by cycling.xml variables for convenience
#
# DATE_STR       = defined by the ANAL_TIME variable, to be used as path
#                  name variable in YYMMDDHH format 
#####################################################

if [ ! "${ANAL_TIME}" ]; then
  echo "ERROR: \$ANAL_TIME is not defined!"
  exit 1
fi

# Define directory path name variable DATE_STR=YYMMDDHH from ANAL_TIME
HH=`echo $ANAL_TIME | cut -c9-10`
ANAL_DATE=`echo $ANAL_TIME | cut -c1-8`
DATE_STR=`${DATE} +%Y-%m-%d_%H:%M:%S -d "${ANAL_DATE} $HH hours"`

if [ -z "${DATE_STR}"]; then
  echo "ERROR: \$DATE_STR is not defined correctly, check format of \$ANAL_DATE!"
  exit 1
fi

if [ ! "${GSI_ROOT}" ]; then
  echo "ERROR: \$GSI_ROOT is not defined!"
  exit 1
fi

if [ -z "${CRTM_VERSION}" ]; then
  echo "ERROR: The variable \$CRTM_VERSION must be set to version number for specifying binary path!"
  exit 1
fi

if [ ! "${INPUT_DATAROOT}" ]; then
  echo "ERROR: \$INPUT_DATAROOT is not defined!"
  exit 1
fi

if [ ! "${MPIRUN}" ]; then
  echo "ERROR: \$MPIRUN is not defined!"
  exit 1
fi

#####################################################
# The following paths are relative to cycling.xml supplied root paths
#
# WORK_ROOT    = working directory where GSI runs
# OBS_ROOT     = path of observations files
# BKG_ROOT     = path for root directory of background file and ensemble members
# ENS_ROOT     = path where ensemble background files exist, not required
#                if not running hybrid EnVAR  
# FIX_ROOT     = path of fix files
# GSI_EXE      = path and name of the gsi.x executable 
# CRTM_ROOT    = path of the CRTM root directory, contained in GSI_ROOT 
# PREPBUFR     = path of PreBUFR conventional obs
# BKG_FILE     = path and name of background file
# BKG_FILE_mem = path and base for ensemble members, only applies IF_OBSERVER = Yes
#####################################################

WORK_ROOT=${INPUT_DATAROOT}/gsiprd
OBS_ROOT=${INPUT_DATAROOT}/obs
BKG_ROOT=${INPUT_DATAROOT}/bkg
ENS_ROOT=${INPUT_DATAROOT}/gfsens
FIX_ROOT=${GSI_ROOT}/fix

GSI_EXE=${GSI_ROOT}/build/bin/gsi.x
GSI_NAMELIST=${GSI_ROOT}/ush/comgsi_namelist.sh
CRTM_ROOT=${GSI_ROOT}/CRTM_v${CRTM_VERSION}
# NOTE: will likely need to reset the following in generalized script 
PREPBUFR=${OBS_ROOT}/nam.t${HH}z.prepbufr.tm00

if [ ! -d "${OBS_ROOT}" ]; then
  echo "ERROR: OBS_ROOT directory '${OBS_ROOT}' does not exist!"
  exit 1
fi

if [ ! -d "${BKG_ROOT}" ]; then
  echo "ERROR: BKG_ROOT directory '${BKG_ROOT}' does not exist!"
  exit 1
fi

if [ ${IF_HYBRID} = Yes ] ; then
  # ensembles are only required for hybrid EnVAR
  if [ ! -d "${ENS_ROOT}" ]; then
    echo "ERROR: ENS_ROOT directory '${ENS_ROOT}' does not exist!"
    exit 1
  fi
fi
  
if [ ! -d "${FIX_ROOT}" ]; then
  echo "ERROR: FIX directory '${FIX_ROOT}' does not exist!"
  exit 1
fi

if [ ! -x "${GSI_EXE}" ]; then
  echo "ERROR: ${GSI_EXE} does not exist!"
  exit 1
fi

if [ ! -x "${GSI_NAMELIST}" ]; then
  echo "ERROR: ${GSI_NAMELIST} does not exist!"
  exit 1
fi

if [ ! -d "${CRTM_ROOT}" ]; then
  echo "ERROR: CRTM directory '${CRTM_ROOT}' does not exist!"
  exit 1
fi

# NOTE: THIS IS COMMENTED FOR DEBUGGING UNTIL THIS
# VARIABLE IS BETTER UNDERSTOOD.  THIS READ CHECK IS NEW TO
# DRIVER CODE AND BREAKS THE TUTORIAL
#if [ ! -r "${PREPBUFR}" ]; then
#  echo "ERROR: file '${PREPBUFR}' does not exist!"
#  exit 1
#fi

# NOTE: BKG_FILE only currently dynamically links to the d01 with date string
# for the background, probably need to update this later for multiple domains
BKG_FILE=${BKG_ROOT}/wrfout_d01_${DATE_STR}
BKG_FILE_mem=${BKG_ROOT}/wrfarw.mem

if [ ! -r "${BKG_FILE}" ]; then
  echo "ERROR: background file ${BKG_FILE} does not exist!"
  exit 1
fi

#####################################################
# Prep steps for GSI 3D/4D hybrid EnVAR
#####################################################

if [ ${IF_HYBRID} = Yes ] ; then
  PDYa=`echo $ANAL_TIME | cut -c1-8`
  cyca=`echo $ANAL_TIME | cut -c9-10`
  gdate=`date -u -d "$PDYa $cyca -6 hour" +%Y%m%d%H` #guess date is 6hr ago
  gHH=`echo $gdate |cut -c9-10`
  datem1=`date -u -d "$PDYa $cyca -1 hour" +%Y-%m-%d_%H:%M:%S` #1hr ago
  datep1=`date -u -d "$PDYa $cyca 1 hour"  +%Y-%m-%d_%H:%M:%S`  #1hr later
  if [ ${IF_NEMSIO} = Yes ]; then
    if_gfs_nemsio='.true.'
    ENSEMBLE_FILE_mem=${ENS_ROOT}/gdas.t${gHH}z.atmf006s.mem
  else
    if_gfs_nemsio='.false.'
    ENSEMBLE_FILE_mem=${ENS_ROOT}/sfg_${gdate}_fhr06s_mem
  fi

  if [ ${IF_4DENVAR} = Yes ] ; then
    BKG_FILE_P1=${BKG_ROOT}/wrfout_d01_${datep1}
    BKG_FILE_M1=${BKG_ROOT}/wrfout_d01_${datem1}

    if [ ${IF_NEMSIO} = Yes ]; then
      ENSEMBLE_FILE_mem_p1=${ENS_ROOT}/gdas.t${gHH}z.atmf009s.mem
      ENSEMBLE_FILE_mem_m1=${ENS_ROOT}/gdas.t${gHH}z.atmf003s.mem
    else
      ENSEMBLE_FILE_mem_p1=${ENS_ROOT}/sfg_${gdate}_fhr09s_mem
      ENSEMBLE_FILE_mem_m1=${ENS_ROOT}/sfg_${gdate}_fhr03s_mem
    fi
  fi
fi

ifhyb=.false.
if [ ${IF_HYBRID} = Yes ] ; then
  ls ${ENSEMBLE_FILE_mem}* > filelist02
  if [ ${IF_4DENVAR} = Yes ] ; then
    ls ${ENSEMBLE_FILE_mem_p1}* > filelist03
    ls ${ENSEMBLE_FILE_mem_m1}* > filelist01
  fi
  
  nummem=`more filelist02 | wc -l`
  nummem=$((nummem -3 ))

  if [[ ${nummem} -ge 5 ]]; then
    ifhyb=.true.
    ${ECHO} " GSI hybrid uses ${ENSEMBLE_FILE_mem} with n_ens=${nummem}"
  fi
fi
if4d=.false.
if [[ ${ifhyb} = .true. && ${IF_4DENVAR} = Yes ]] ; then
  if4d=.true.
fi

#####################################################
# Begin pre-GSI setup
#####################################################
# Create the ram work directory and cd into it

workdir=${WORK_ROOT}
echo " Create working directory:" ${workdir}

if [ -d "${workdir}" ]; then
  rm -rf ${workdir}
fi
mkdir -p ${workdir}
cd ${workdir}

echo " Copy background file and link observation bufr to working directory"

# Copy over background field -- THIS IS MODIFIED BY GSI DO NOT LINK TO IT
cp ${BKG_FILE} ./wrf_inout
if [ ${IF_4DENVAR} = Yes ] ; then
  cp ${BKG_FILE_P1} ./wrf_inou3
  cp ${BKG_FILE_M1} ./wrf_inou1
fi

# Link to the prepbufr data
ln -s ${PREPBUFR} ./prepbufr
# ln -s ${OBS_ROOT}/gdas1.t${HH}z.sptrmm.tm00.bufr_d tmirrbufr

# Link to the radiance data
ii=1
if [ ${IF_SATRAD} = Yes ] ; then
   srcobsfile[1]=${OBS_ROOT}/gdas1.t${HH}z.satwnd.tm00.bufr_d
   gsiobsfile[1]=satwnd
   srcobsfile[2]=${OBS_ROOT}/gdas1.t${HH}z.1bamua.tm00.bufr_d
   gsiobsfile[2]=amsuabufr
   srcobsfile[3]=${OBS_ROOT}/gdas1.t${HH}z.1bhrs4.tm00.bufr_d
   gsiobsfile[3]=hirs4bufr
   srcobsfile[4]=${OBS_ROOT}/gdas1.t${HH}z.1bmhs.tm00.bufr_d
   gsiobsfile[4]=mhsbufr
   srcobsfile[5]=${OBS_ROOT}/gdas1.t${HH}z.1bamub.tm00.bufr_d
   gsiobsfile[5]=amsubbufr
   srcobsfile[6]=${OBS_ROOT}/gdas1.t${HH}z.ssmisu.tm00.bufr_d
   gsiobsfile[6]=ssmirrbufr
   # srcobsfile[7]=${OBS_ROOT}/gdas1.t${HH}z.airsev.tm00.bufr_d
   gsiobsfile[7]=airsbufr
   srcobsfile[8]=${OBS_ROOT}/gdas1.t${HH}z.sevcsr.tm00.bufr_d
   gsiobsfile[8]=seviribufr
   srcobsfile[9]=${OBS_ROOT}/gdas1.t${HH}z.iasidb.tm00.bufr_d
   gsiobsfile[9]=iasibufr
   srcobsfile[10]=${OBS_ROOT}/gdas1.t${HH}z.gpsro.tm00.bufr_d
   gsiobsfile[10]=gpsrobufr
   srcobsfile[11]=${OBS_ROOT}/gdas1.t${HH}z.amsr2.tm00.bufr_d
   gsiobsfile[11]=amsrebufr
   srcobsfile[12]=${OBS_ROOT}/gdas1.t${HH}z.atms.tm00.bufr_d
   gsiobsfile[12]=atmsbufr
   srcobsfile[13]=${OBS_ROOT}/gdas1.t${HH}z.geoimr.tm00.bufr_d
   gsiobsfile[13]=gimgrbufr
   srcobsfile[14]=${OBS_ROOT}/gdas1.t${HH}z.gome.tm00.bufr_d
   gsiobsfile[14]=gomebufr
   srcobsfile[15]=${OBS_ROOT}/gdas1.t${HH}z.omi.tm00.bufr_d
   gsiobsfile[15]=omibufr
   srcobsfile[16]=${OBS_ROOT}/gdas1.t${HH}z.osbuv8.tm00.bufr_d
   gsiobsfile[16]=sbuvbufr
   srcobsfile[17]=${OBS_ROOT}/gdas1.t${HH}z.eshrs3.tm00.bufr_d
   gsiobsfile[17]=hirs3bufrears
   srcobsfile[18]=${OBS_ROOT}/gdas1.t${HH}z.esamua.tm00.bufr_d
   gsiobsfile[18]=amsuabufrears
   srcobsfile[19]=${OBS_ROOT}/gdas1.t${HH}z.esmhs.tm00.bufr_d
   gsiobsfile[19]=mhsbufrears
   srcobsfile[20]=${OBS_ROOT}/rap.t${HH}z.nexrad.tm00.bufr_d
   gsiobsfile[20]=l2rwbufr
   srcobsfile[21]=${OBS_ROOT}/rap.t${HH}z.lgycld.tm00.bufr_d
   gsiobsfile[21]=larcglb
   srcobsfile[22]=${OBS_ROOT}/gdas1.t${HH}z.glm.tm00.bufr_d
   gsiobsfile[22]=
   while [[ $ii -le 21 ]]; do
      if [ -r "${srcobsfile[$ii]}" ]; then
         ln -s ${srcobsfile[$ii]}  ${gsiobsfile[$ii]}
         echo "link source obs file ${srcobsfile[$ii]}"
      fi
      (( ii = $ii + 1 ))
   done
fi

echo " Copy fixed files and link CRTM coefficient files to working directory"

#####################################################
# Set fixed files
#
#   berror    = forecast model background error statistics
#   specoef   = CRTM spectral coefficients
#   trncoef   = CRTM transmittance coefficients
#   emiscoef  = CRTM coefficients for IR sea surface emissivity model
#   aerocoef  = CRTM coefficients for aerosol effects
#   cldcoef   = CRTM coefficients for cloud effects
#   satinfo   = text file with information about assimilation of brightness temperatures
#   satangl   = angle dependent bias correction file (fixed in time)
#   pcpinfo   = text file with information about assimilation of prepcipitation rates
#   ozinfo    = text file with information about assimilation of ozone data
#   errtable  = text file with obs error for conventional data (regional only)
#   convinfo  = text file with information about assimilation of conventional data
#   lightinfo = text file with information about assimilation of GLM lightning data
#   bufrtable = text file ONLY needed for single obs test (oneobstest=.true.)
#   bftab_sst = bufr table for sst ONLY needed for sst retrieval (retrieval=.true.)
#####################################################

if [ ${bkcv_option} = GLOBAL ] ; then
  echo ' Use global background error covariance'
  BERROR=${FIX_ROOT}/${BYTE_ORDER}/nam_glb_berror.f77.gcv
  OBERROR=${FIX_ROOT}/prepobs_errtable.global
  if [ ${bk_core} = NMM ] ; then
     ANAVINFO=${FIX_ROOT}/anavinfo_ndas_netcdf_glbe
  fi
  if [ ${bk_core} = ARW ] ; then
    ANAVINFO=${FIX_ROOT}/anavinfo_arw_netcdf_glbe
  fi
  if [ ${bk_core} = NMMB ] ; then
    ANAVINFO=${FIX_ROOT}/anavinfo_nems_nmmb_glb
  fi
else
  echo ' Use NAM background error covariance'
  BERROR=${FIX_ROOT}/${BYTE_ORDER}/nam_nmmstat_na.gcv
  OBERROR=${FIX_ROOT}/nam_errtable.r3dv
  if [ ${bk_core} = NMM ] ; then
     ANAVINFO=${FIX_ROOT}/anavinfo_ndas_netcdf
  fi
  if [ ${bk_core} = ARW ] ; then
     ANAVINFO=${FIX_ROOT}/anavinfo_arw_netcdf
  fi
  if [ ${bk_core} = NMMB ] ; then
     ANAVINFO=${FIX_ROOT}/anavinfo_nems_nmmb
  fi
fi

SATANGL=${FIX_ROOT}/global_satangbias.txt
SATINFO=${FIX_ROOT}/global_satinfo.txt
CONVINFO=${FIX_ROOT}/global_convinfo.txt
OZINFO=${FIX_ROOT}/global_ozinfo.txt
PCPINFO=${FIX_ROOT}/global_pcpinfo.txt
LIGHTINFO=${FIX_ROOT}/global_lightinfo.txt

#  copy Fixed fields to working directory
cp $ANAVINFO anavinfo
cp $BERROR   berror_stats
cp $SATANGL  satbias_angle
cp $SATINFO  satinfo
cp $CONVINFO convinfo
cp $OZINFO   ozinfo
cp $PCPINFO  pcpinfo
cp $LIGHTINFO lightinfo
cp $OBERROR  errtable

# CRTM Spectral and Transmittance coefficients
CRTM_ROOT_ORDER=${CRTM_ROOT}/${BYTE_ORDER}
emiscoef_IRwater=${CRTM_ROOT_ORDER}/Nalli.IRwater.EmisCoeff.bin
emiscoef_IRice=${CRTM_ROOT_ORDER}/NPOESS.IRice.EmisCoeff.bin
emiscoef_IRland=${CRTM_ROOT_ORDER}/NPOESS.IRland.EmisCoeff.bin
emiscoef_IRsnow=${CRTM_ROOT_ORDER}/NPOESS.IRsnow.EmisCoeff.bin
emiscoef_VISice=${CRTM_ROOT_ORDER}/NPOESS.VISice.EmisCoeff.bin
emiscoef_VISland=${CRTM_ROOT_ORDER}/NPOESS.VISland.EmisCoeff.bin
emiscoef_VISsnow=${CRTM_ROOT_ORDER}/NPOESS.VISsnow.EmisCoeff.bin
emiscoef_VISwater=${CRTM_ROOT_ORDER}/NPOESS.VISwater.EmisCoeff.bin
emiscoef_MWwater=${CRTM_ROOT_ORDER}/FASTEM6.MWwater.EmisCoeff.bin
aercoef=${CRTM_ROOT_ORDER}/AerosolCoeff.bin
cldcoef=${CRTM_ROOT_ORDER}/CloudCoeff.bin

ln -s $emiscoef_IRwater ./Nalli.IRwater.EmisCoeff.bin
ln -s $emiscoef_IRice ./NPOESS.IRice.EmisCoeff.bin
ln -s $emiscoef_IRsnow ./NPOESS.IRsnow.EmisCoeff.bin
ln -s $emiscoef_IRland ./NPOESS.IRland.EmisCoeff.bin
ln -s $emiscoef_VISice ./NPOESS.VISice.EmisCoeff.bin
ln -s $emiscoef_VISland ./NPOESS.VISland.EmisCoeff.bin
ln -s $emiscoef_VISsnow ./NPOESS.VISsnow.EmisCoeff.bin
ln -s $emiscoef_VISwater ./NPOESS.VISwater.EmisCoeff.bin
ln -s $emiscoef_MWwater ./FASTEM6.MWwater.EmisCoeff.bin
ln -s $aercoef  ./AerosolCoeff.bin
ln -s $cldcoef  ./CloudCoeff.bin

# Copy CRTM coefficient files based on entries in satinfo file
for file in `awk '{if($1!~"!"){print $1}}' ./satinfo | sort | uniq` ;do
   ln -s ${CRTM_ROOT_ORDER}/${file}.SpcCoeff.bin ./
   ln -s ${CRTM_ROOT_ORDER}/${file}.TauCoeff.bin ./
done

# Only need this file for single obs test
bufrtable=${FIX_ROOT}/prepobs_prep.bufrtable
cp $bufrtable ./prepobs_prep.bufrtable

# for satellite bias correction
# NOTE: may need to use own satbias files for appropriate bias correction
cp ${GSI_ROOT}/fix/comgsi_satbias_in ./satbias_in
cp ${GSI_ROOT}/fix/comgsi_satbias_pc_in ./satbias_pc_in 

#####################################################
# Build GSI namelist
#####################################################
echo " Build the namelist "

# default is NAM
#   as_op='1.0,1.0,0.5 ,0.7,0.7,0.5,1.0,1.0,'
vs_op='1.0,'
hzscl_op='0.373,0.746,1.50,'

if [ ${bkcv_option} = GLOBAL ] ; then
#   as_op='0.6,0.6,0.75,0.75,0.75,0.75,1.0,1.0'
   vs_op='0.7,'
   hzscl_op='1.7,0.8,0.5,'
fi

if [ ${bk_core} = NMMB ] ; then
   vs_op='0.6,'
fi

# default is NMM
bk_core_arw='.false.'
bk_core_nmm='.true.'
bk_core_nmmb='.false.'
bk_if_netcdf='.true.'

if [ ${bk_core} = ARW ] ; then
   bk_core_arw='.true.'
   bk_core_nmm='.false.'
   bk_core_nmmb='.false.'
   bk_if_netcdf='.true.'
fi

if [ ${bk_core} = NMMB ] ; then
   bk_core_arw='.false.'
   bk_core_nmm='.false.'
   bk_core_nmmb='.true.'
   bk_if_netcdf='.false.'
fi

if [ ${IF_OBSERVER} = Yes ] ; then
  nummiter=0
  if_read_obs_save='.true.'
  if_read_obs_skip='.false.'
else
  nummiter=2
  if_read_obs_save='.false.'
  if_read_obs_skip='.false.'
fi

# Build the GSI namelist on-the-fly
. $GSI_NAMELIST

# modify the anavinfo vertical levels based on wrf_inout for WRF ARW and NMM
if [ ${bk_core} = ARW ] || [ ${bk_core} = NMM ] ; then
bklevels=`ncdump -h wrf_inout | grep "bottom_top =" | awk '{print $3}' `
bklevels_stag=`ncdump -h wrf_inout | grep "bottom_top_stag =" | awk '{print $3}' `
anavlevels=`cat anavinfo | grep ' sf ' | tail -1 | awk '{print $2}' `  # levels of sf, vp, u, v, t, etc
anavlevels_stag=`cat anavinfo | grep ' prse ' | tail -1 | awk '{print $2}' `  # levels of prse
sed -i 's/ '$anavlevels'/ '$bklevels'/g' anavinfo
sed -i 's/ '$anavlevels_stag'/ '$bklevels_stag'/g' anavinfo
fi

#####################################################
# Run GSI
#####################################################
# Print run parameters
${ECHO}
${ECHO} "gsi.ksh started at `${DATE}`"
${ECHO}
${ECHO} "IF_SATRAD      = ${IF_SATRAD}"    
${ECHO} "IF_OBSERVER    = ${IF_OBSERVER}"
${ECHO} "NO_MEMBER      = ${NO_MEMBER}"
${ECHO} "IF_HYBRID      = ${IF_HYBRID}"
${ECHO} "IF_4DENVAR     = ${IF_4DENVAR}"
${ECHO} "IF_NEMSIO      = ${IF_NEMSIO}"
${ECHO} "IF_ONEOB       = ${IF_ONEOB}"
${ECHO}
${ECHO} "ANAL_TIME      = ${ANAL_TIME}"
${ECHO} "GSI_ROOT       = ${GSI_ROOT}"
${ECHO} "CRTM_VERSION   = ${CRTM_VERSION}"
${ECHO} "STATIC_DATA    = ${STATIC_DATA}"
${ECHO} "INPUT_DATAROOT = ${INPUT_DATAROOT}"
${ECHO}

echo ' Run GSI with' ${bk_core} 'background'
${MPIRUN} ${GSI_EXE} > stdout.anl.${ANAL_TIME} 2>&1

#####################################################
# Run time error check
#####################################################
error=$?

if [ ${error} -ne 0 ]; then
  echo "ERROR: ${GSI} crashed  Exit status=${error}"
  exit ${error}
fi

#####################################################
# GSI updating satbias_in
#####################################################
# GSI updating satbias_in (only for cycling assimilation)

# Copy the output to more understandable names
ln -s wrf_inout   wrfanl.${ANAL_TIME}
ln -s fort.201    fit_p1.${ANAL_TIME}
ln -s fort.202    fit_w1.${ANAL_TIME}
ln -s fort.203    fit_t1.${ANAL_TIME}
ln -s fort.204    fit_q1.${ANAL_TIME}
ln -s fort.207    fit_rad1.${ANAL_TIME}

#####################################################
# Loop over first and last outer loops to generate innovation
# diagnostic files for indicated observation types (groups)
#
# NOTE:  Since we set miter=2 in GSI namelist SETUP, outer
#        loop 03 will contain innovations with respect to
#        the analysis.  Creation of o-a innovation files
#        is triggered by write_diag(3)=.true.  The setting
#        write_diag(1)=.true. turns on creation of o-g
#        innovation files.
#
#####################################################

loops="01 03"
for loop in $loops; do

case $loop in
  01) string=ges;;
  03) string=anl;;
   *) string=$loop;;
esac

#####################################################
#  Collect diagnostic files for obs types (groups) below
#   listall="conv amsua_metop-a mhs_metop-a hirs4_metop-a hirs2_n14 msu_n14 \
#          sndr_g08 sndr_g10 sndr_g12 sndr_g08_prep sndr_g10_prep sndr_g12_prep \
#          sndrd1_g08 sndrd2_g08 sndrd3_g08 sndrd4_g08 sndrd1_g10 sndrd2_g10 \
#          sndrd3_g10 sndrd4_g10 sndrd1_g12 sndrd2_g12 sndrd3_g12 sndrd4_g12 \
#          hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 \
#          amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua \
#          goes_img_g08 goes_img_g10 goes_img_g11 goes_img_g12 \
#          pcp_ssmi_dmsp pcp_tmi_trmm sbuv2_n16 sbuv2_n17 sbuv2_n18 \
#          omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 amsua_n18 mhs_n18 \
#          amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 \
#          ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 mhs_metop_b \
#          hirs4_metop_b hirs4_n19 amusa_n19 mhs_n19 goes_glm_16"
#####################################################
 listall=`ls pe* | cut -f2 -d"." | awk '{print substr($0, 0, length($0)-3)}' | sort | uniq `

   for type in $listall; do
      count=`ls pe*${type}_${loop}* | wc -l`
      if [[ $count -gt 0 ]]; then
         cat pe*${type}_${loop}* > diag_${type}_${string}.${ANAL_TIME}
      fi
   done
done

#  Clean working directory to save only important files 
ls -l * > list_run_directory
if [[ ${if_clean} = clean && ${IF_OBSERVER} != Yes ]]; then
  echo ' Clean working directory after GSI run'
  rm -f *Coeff.bin     # all CRTM coefficient files
  rm -f pe0*           # diag files on each processor
  rm -f obs_input.*    # observation middle files
  rm -f siganl sigf0?  # background middle files
  rm -f fsize_*        # delete temperal file for bufr size
fi

#####################################################
# start to calculate diag files for each member
#####################################################

if [ ${IF_OBSERVER} = Yes ] ; then
  string=ges
  for type in $listall; do
    count=0
    if [[ -f diag_${type}_${string}.${ANAL_TIME} ]]; then
       mv diag_${type}_${string}.${ANAL_TIME} diag_${type}_${string}.ensmean
    fi
  done
  mv wrf_inout wrf_inout_ensmean

# Build the GSI namelist on-the-fly for each member
  nummiter=0
  if_read_obs_save='.false.'
  if_read_obs_skip='.true.'
. $GSI_NAMELIST

# Loop through each member
  loop="01"
  ensmem=1
  while [[ $ensmem -le $NO_MEMBER ]];do

     rm pe0*

     print "\$ensmem is $ensmem"
     ensmemid=`printf %3.3i $ensmem`

# get new background for each member
     if [[ -f wrf_inout ]]; then
       rm wrf_inout
     fi

     BKG_FILE=${BKG_FILE_mem}${ensmemid}
     echo $BKG_FILE
     ln -s $BKG_FILE wrf_inout

#  run  GSI
     echo ' Run GSI with' ${bk_core} 'for member ', ${ensmemid}
     ${MPIRUN} ${GSI_EXE} > stdout_mem${ensmemid} 2>&1

#  run time error check and save run time file status
     error=$?

     if [ ${error} -ne 0 ]; then
       echo "ERROR: ${GSI} crashed for member ${ensmemid} Exit status=${error}"
       exit ${error}
     fi

     ls -l * > list_run_directory_mem${ensmemid}

# generate diag files

     for type in $listall; do
           count=`ls pe*${type}_${loop}* | wc -l`
        if [[ $count -gt 0 ]]; then
           cat pe*${type}_${loop}* > diag_${type}_${string}.mem${ensmemid}
        fi
     done

# next member
     (( ensmem += 1 ))
      
  done

fi

${ECHO} "gsi.ksh completed successfully at `${DATE}`"

exit 0
