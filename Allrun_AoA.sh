#!/bin/sh
cd ${0%/*} || exit 1    # Run from this directory

# Source tutorial run functions
. $WM_PROJECT_DIR/bin/tools/RunFunctions

# ==========================
# User settings
# ==========================
BASE=base_case          # base case folder
SOLVER=simpleFoam
ANGLES="-30 -20 -10 -8 -6 -4 -2 0 2 4 6 8 10 12 20 25 30"
SPEEDS="10 20 30"   # m/s

NPROC=12
#AVG_WINDOW=100

# Center of gravity
xCG=0.34
yCG=0.0
zCG=1.0

for U in $SPEEDS; do
    for A in $ANGLES; do
        #CASE="AoA_${A}"
        CASE="case/U${U}_AoA_${A}"
        #echo "=== AoA = ${A} deg ==="
        echo "=== U = ${U} m/s, AoA = ${A} deg ==="

        # -----------------------
        # 1) Copy base case
        # -----------------------
        rm -rf "$CASE"
        cp -r "$BASE" "$CASE"
        cd "$CASE" || exit 1

        # -----------------------
        # Update flowVelocity in include/initialConditions
        # -----------------------
        sed -i "s/flowVelocity.*/flowVelocity    (${U} 0 0);/" 0/include/initialConditions

        # -----------------------
        # Update magUInf in system/forceCoeffs
        # -----------------------
        sed -i "s/magUInf.*/magUInf        $U;/" system/forceCoeffs

        # -----------------------
        # 2) Rotate STL geometry before meshing
        # -----------------------
        # Assuming geometry is in constant/triSurface/airfoil.stl
        #transformPoints "Ry=$A" constant/geometry/uav.stl
        #surfaceTransformPoints "Ry=$A" constant/geometry/uav.stl constant/geometry/uav.stl
        surfaceTransformPoints "translate=(-$xCG -$yCG -$zCG), Ry=$A, translate=($xCG $yCG $zCG)" constant/geometry/uav.stl constant/geometry/uav.stl


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
        # -----------------------<
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

        cd ..
        cd ..
    done
done

echo "=== Parallel AoA sweep finished. Results in $OUT ==="
