#!/bin/sh
cd ${0%/*} || exit 1    # Run from this directory

# Source tutorial run functions
. $WM_PROJECT_DIR/bin/tools/RunFunctions

# ==========================
# User settings
# ==========================
BASE=base_case          # base case folder
SOLVER=simpleFoam
ANGLES="-4 -3 -2 -1 0 1 2 3 4 5 6 7 8 9 10 11 12"
#ANGLES="0"
NPROC=12
AVG_WINDOW=100
OUT=AoA_results.dat

#FORCE_PATCH="wing_surface"
Aref=0.75
lRef=0.5
CofR="0.135 0 0"
# ==========================

echo "# AoA  time_last  Cd_mean  Cl_mean  Cm_mean  Cd_last  Cl_last  Cm_last" > "$OUT"

for A in $ANGLES; do
    CASE="AoA_${A}"
    echo "=== AoA = ${A} deg ==="

    # -----------------------
    # 1) Copy base case
    # -----------------------
    rm -rf "$CASE"
    cp -r "$BASE" "$CASE"
    cd "$CASE" || exit 1

    # -----------------------
    # 2) Rotate STL geometry before meshing
    # -----------------------
    # Assuming geometry is in constant/triSurface/airfoil.stl
    #transformPoints "Ry=$A" constant/geometry/uav.stl
    surfaceTransformPoints "Ry=$A" constant/geometry/uav.stl constant/geometry/uav.stl

    # -----------------------
    # 3) Mesh creation
    # -----------------------
    rm -rf processor*
    runApplication surfaceFeatures
    runApplication blockMesh
    runApplication decomposePar -copyZero
    runParallel snappyHexMesh

    # -----------------------
    # 4) Decompose for solver
    # -----------------------
    runApplication decomposePar -copyZero

    # -----------------------
    # 5) Run initialization and solver
    # -----------------------
    runParallel potentialFoam
    runParallel $SOLVER

    # -----------------------
    # 6) Reconstruct results
    # -----------------------
    runApplication reconstructPar -latestTime

    # -----------------------
    # 7) Extract force coefficients
    # -----------------------
    coeffFile=$(ls -1 postProcessing/forceCoeffs/*/forceCoeffs.dat | tail -n1)

    # Parse header
    header=$(grep -m1 "^# Time" "$coeffFile")
    colTime=1; colCm=2; colCd=3; colCl=4
    i=1
    for token in $header; do
        case "$token" in
            Time) colTime=$i ;;
            Cm)   colCm=$i ;;
            Cd)   colCd=$i ;;
            Cl)   colCl=$i ;;
        esac
        i=$((i+1))
    done

    # Last line
    lastLine=$(grep -v "^#" "$coeffFile" | tail -n1)
    time_last=$(echo "$lastLine" | awk -v t=$colTime '{print $t}')
    Cd_last=$(  echo "$lastLine" | awk -v c=$colCd  '{print $c}')
    Cl_last=$(  echo "$lastLine" | awk -v c=$colCl  '{print $c}')
    Cm_last=$(  echo "$lastLine" | awk -v c=$colCm  '{print $c}')

    # Mean over last N samples
    Cd_mean=$(grep -v "^#" "$coeffFile" | tail -n "$AVG_WINDOW" | awk -v c=$colCd '{s+=$c; n++} END{if(n) printf("%.8g", s/n)}')
    Cl_mean=$(grep -v "^#" "$coeffFile" | tail -n "$AVG_WINDOW" | awk -v c=$colCl '{s+=$c; n++} END{if(n) printf("%.8g", s/n)}')
    Cm_mean=$(grep -v "^#" "$coeffFile" | tail -n "$AVG_WINDOW" | awk -v c=$colCm '{s+=$c; n++} END{if(n) printf("%.8g", s/n)}')

    # Append results
    echo "$A  $time_last  $Cd_mean  $Cl_mean  $Cm_mean  $Cd_last  $Cl_last  $Cm_last" >> "../$OUT"

    cd ..
done

echo "=== Parallel AoA sweep finished. Results in $OUT ==="
