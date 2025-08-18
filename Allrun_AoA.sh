#!/bin/sh
cd ${0%/*} || exit 1    # Run from this directory

# Source tutorial run functions
. $WM_PROJECT_DIR/bin/tools/RunFunctions

# ==========================
# User settings
# ==========================
BASE=base_case          # base case folder
SOLVER=simpleFoam
ANGLES="-5 -4 -3 -2 -1 0 1 2 3 4 5 6 7 8 9 10"
NPROC=12
AVG_WINDOW=100
OUT=AoA_results.dat

FORCE_PATCH="wing_surface"
Aref=0.31
lRef=0.271
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
    # 2) Mesh creation
    # -----------------------
    #rm -rf processor*
    runApplication surfaceFeatures
    runApplication blockMesh

    # Update decomposeParDict to match NPROC
    #sed -i "s/numberOfSubdomains.*/numberOfSubdomains $NPROC;/" system/decomposeParDict

    runApplication decomposePar -copyZero
    runParallel snappyHexMesh

    # -----------------------
    # 3) Rotate mesh for AoA
    # -----------------------
    transformPoints "Ry=$A"

    # -----------------------
    # 4) Re-decompose for solver
    # -----------------------
    #rm -rf processor*
    runApplication decomposePar -copyZero

    # -----------------------
    # 5) Update forceCoeffs
    # -----------------------
#    cat > system/forceCoeffs <<EOF
#type            forceCoeffs;
#libs            ("libforces.so");

#writeControl    timeStep;
#timeInterval    1;
#log             yes;

#patches         ($FORCE_PATCH);

#rho             rhoInf;
#rhoInf          1;

#liftDir         (0 0 1);
#dragDir         (1 0 0);
#pitchAxis       (0 1 0);
#CofR            ($CofR);
#magUInf         20;
#lRef            $lRef;
#Aref            $Aref;
#EOF

    # -----------------------
    # 6) Run initialization and solver in parallel
    # -----------------------
    runParallel patchSummary
    runParallel potentialFoam
    runParallel $SOLVER

    # -----------------------
    # 7) Reconstruct results
    # -----------------------
    runApplication reconstructPar -latestTime

    # -----------------------
    # 8) Extract force coefficients
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
