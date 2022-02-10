// -*- compile-command: "cd ../ && ./compile_console.sh && ./test_castle_game_engine --suite=TTestCastleFrustum" -*-
{
  Copyright 2005-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

unit TestCastleFrustum;

interface

uses
  Classes, SysUtils, FpcUnit, TestUtils, TestRegistry,
  CastleTestCase, CastleVectors, CastleBoxes, CastleFrustum;

type
  TTestCastleFrustum = class(TCastleTestCase)
  private
    procedure AssertFrustumSphereCollisionPossible(const Frustum: TFrustum;
      const SphereCenter: TVector3; const SphereRadiusSqt: Single;
      const GoodResult: TFrustumCollisionPossible);
    procedure AssertFrustumBox3DCollisionPossible(const Frustum: TFrustum;
      const Box3D: TBox3D; const GoodResult: TFrustumCollisionPossible);
  published
    procedure TestFrustum;
    procedure TestInfiniteFrustum;
    procedure TestCompareWithUnoptimizedPlaneCollision;
    procedure TestTransformFrustum;
  end;

implementation

uses Math,
  CastleUtils, CastleTimeUtils, CastleProjection, CastleTransform, CastleLog;

function RandomFrustum(MakeZFarInfinity: boolean): TFrustum;

  function RandomNonZeroVector(const Scale: Float): TVector3;
  begin
    repeat
      Result.X := Random * Scale - Scale/2;
      Result.Y := Random * Scale - Scale/2;
      Result.Z := Random * Scale - Scale/2;
    until not Result.IsPerfectlyZero;
  end;

var
  ZFar: Single;
begin
  if MakeZFarInfinity then
    ZFar := ZFarInfinity
  else
    ZFar := Random * 100 + 100;
  Result.Init(
    PerspectiveProjectionMatrixDeg(
      Random * 30 + 60,
      Random * 0.5 + 0.7,
      Random * 5 + 1,
      ZFar),
    LookDirMatrix(
      { Don't randomize camera pos too much, as we want some non-trivial
        collisions with boxes generated by RandomBox. }
      RandomNonZeroVector(10),
      RandomNonZeroVector(1),
      RandomNonZeroVector(1)));
end;

function RandomBox: TBox3D;
var
  I: Integer;
  Val1, Val2: Single;
begin
  for I := 0 to 2 do
  begin
    Val1 := Random * 20 - 10;
    Val2 := Random * 20 - 10;
    OrderUp(Val1, Val2);
    {$warnings off} // silence FPC warning about Normal uninitialized
    Result.Data[0].Data[I] := Val1;
    {$warnings on}
    Result.Data[1].Data[I] := Val2;
  end;
end;

procedure TTestCastleFrustum.AssertFrustumSphereCollisionPossible(const Frustum: TFrustum;
  const SphereCenter: TVector3; const SphereRadiusSqt: Single;
  const GoodResult: TFrustumCollisionPossible);
begin
 AssertTrue( Frustum.SphereCollisionPossible(SphereCenter,
   SphereRadiusSqt) = GoodResult);

 AssertTrue( Frustum.SphereCollisionPossibleSimple(SphereCenter,
     SphereRadiusSqt) = (GoodResult <> fcNoCollision) );
end;

procedure TTestCastleFrustum.AssertFrustumBox3DCollisionPossible(const Frustum: TFrustum;
  const Box3D: TBox3D; const GoodResult: TFrustumCollisionPossible);
begin
 AssertTrue( Frustum.Box3DCollisionPossible(Box3D) = GoodResult);

 AssertTrue( Frustum.Box3DCollisionPossibleSimple(Box3D) =
   (GoodResult <> fcNoCollision) );
end;

procedure TTestCastleFrustum.TestFrustum;
var
  Frustum: TFrustum;
begin
 { Calculate testing frustum }
 Frustum.Init(
   PerspectiveProjectionMatrixDeg(60, 1, 10, 100),
   LookDirMatrix(
     Vector3(10, 10, 10) { eye position },
     Vector3(1, 0, 0) { look direction },
     Vector3(0, 0, 1) { up vector } ));
 AssertTrue(not Frustum.ZFarInfinity);

 AssertFrustumSphereCollisionPossible(Frustum, Vector3(0, 0, 0), 81,
   fcNoCollision);
 { This is between camera pos and near plane }
 AssertFrustumSphereCollisionPossible(Frustum, Vector3(0, 0, 0), 200,
   fcNoCollision);
 { This should collide with frustum, as it crosses near plane }
 AssertFrustumSphereCollisionPossible(Frustum, Vector3(0, 0, 0), 420,
   fcSomeCollisionPossible);
 AssertFrustumSphereCollisionPossible(Frustum, Vector3(50, 10, 10), 1,
   fcInsideFrustum);
 { This sphere intersects near plane }
 AssertFrustumSphereCollisionPossible(Frustum, Vector3(20, 10, 10), 1,
   fcSomeCollisionPossible);

 AssertFrustumBox3DCollisionPossible(Frustum, TBox3D.Empty, fcNoCollision);
 AssertFrustumBox3DCollisionPossible(Frustum,
   Box3D(Vector3(-1, -1, -1), Vector3(9, 9, 9)),
   fcNoCollision);
 AssertFrustumBox3DCollisionPossible(Frustum,
   Box3D(Vector3(50, 10, 10), Vector3(51, 11, 11)),
   fcInsideFrustum);
 AssertFrustumBox3DCollisionPossible(Frustum,
   Box3D(Vector3(19, 10, 10), Vector3(21, 11, 11)),
   fcSomeCollisionPossible);
end;

procedure TTestCastleFrustum.TestInfiniteFrustum;
var
  Frustum: TFrustum;
begin
  Frustum.Init(
    PerspectiveProjectionMatrixDeg(60, 1, 10, ZFarInfinity),
    LookDirMatrix(
      Vector3(10, 10, 10) { eye position },
      Vector3(1, 0, 0) { look direction },
      Vector3(0, 0, 1) { up vector } ));

  AssertTrue(Frustum.Planes[fpFar].X = 0);
  AssertTrue(Frustum.Planes[fpFar].Y = 0);
  AssertTrue(Frustum.Planes[fpFar].Z = 0);
  AssertTrue(Frustum.ZFarInfinity);

  AssertFrustumSphereCollisionPossible(Frustum, Vector3(0, 0, 0), 81,
    fcNoCollision);
  AssertFrustumSphereCollisionPossible(Frustum, Vector3(100, 10, 10), 1,
    fcInsideFrustum);
  AssertFrustumSphereCollisionPossible(Frustum, Vector3(0, 0, 0), 400,
    fcSomeCollisionPossible);
end;

procedure TTestCastleFrustum.TestCompareWithUnoptimizedPlaneCollision;
{ Compare current Box3DCollisionPossible implementation with older
  implementation that didn't use smart Box3DPlaneCollision,
  instead was testing all 8 corners of bounding box.
  This compares results (should be equal) and speed (hopefully, new
  implementation is much faster!).
}
{ $define WRITELN_TESTS}

  function OldFrustumBox3DCollisionPossible(
    const Frustum: TFrustum;
    const Box: TBox3D): TFrustumCollisionPossible;

  { Note: I tried to optimize this function,
    since it's crucial for TOctree.EnumerateCollidingOctreeItems,
    and this is crucial for TCastleScene.RenderFrustumOctree,
    and this is crucial for overall speed of rendering. }

  var
    fp: TFrustumPlane;
    FrustumMultiplyBox: TBox3D;

    function CheckOutsideCorner(const XIndex, YIndex, ZIndex: Cardinal): boolean;
    begin
     Result :=
       { Frustum[fp].X * Box[XIndex].X +
         Frustum[fp].Y * Box[YIndex].Y +
         Frustum[fp].Z * Box[ZIndex].Z +
         optimized version : }
       FrustumMultiplyBox.Data[XIndex].X +
       FrustumMultiplyBox.Data[YIndex].Y +
       FrustumMultiplyBox.Data[ZIndex].Z +
       Frustum.Planes[fp][3] < 0;
    end;

  var
    InsidePlanesCount: Cardinal;
    LastPlane: TFrustumPlane;
  begin
    with Frustum do
    begin
      InsidePlanesCount := 0;

      LastPlane := High(FP);
      AssertTrue(LastPlane = fpFar);

      { If the frustum has far plane in infinity, then ignore this plane.
        Inc InsidePlanesCount, since the box is inside this infinite plane. }
      if ZFarInfinity then
      begin
        LastPlane := Pred(LastPlane);
        Inc(InsidePlanesCount);
      end;

      { The logic goes like this:
          if box is on the "outside" of *any* of 6 planes, result is NoCollision
          if box is on the "inside" of *all* 6 planes, result is InsideFrustum
          else SomeCollisionPossible. }

      for fp := Low(fp) to LastPlane do
      begin
       { This way I need 6 multiplications instead of 8*3=24
         (in case I would have to execute CheckOutsideCorner 8 times) }
       FrustumMultiplyBox.Data[0].X := Planes[fp].X * Box.Data[0].X;
       FrustumMultiplyBox.Data[0].Y := Planes[fp].Y * Box.Data[0].Y;
       FrustumMultiplyBox.Data[0].Z := Planes[fp].Z * Box.Data[0].Z;
       FrustumMultiplyBox.Data[1].X := Planes[fp].X * Box.Data[1].X;
       FrustumMultiplyBox.Data[1].Y := Planes[fp].Y * Box.Data[1].Y;
       FrustumMultiplyBox.Data[1].Z := Planes[fp].Z * Box.Data[1].Z;

       { I'm splitting code below to two possilibilities.
         This way I can calculate 7 remaining CheckOutsideCorner
         calls using code  like
           "... and ... and ..."
         or
           "... or ... or ..."
         , and this means that short-circuit boolean evaluation
         may usually reduce number of needed CheckOutsideCorner calls
         (i.e. I will not need to actually call CheckOutsideCorner 8 times
         per frustum plane). }

       if CheckOutsideCorner(0, 0, 0) then
       begin
        if CheckOutsideCorner(0, 0, 1) and
           CheckOutsideCorner(0, 1, 0) and
           CheckOutsideCorner(0, 1, 1) and
           CheckOutsideCorner(1, 0, 0) and
           CheckOutsideCorner(1, 0, 1) and
           CheckOutsideCorner(1, 1, 0) and
           CheckOutsideCorner(1, 1, 1) then
         { All 8 corners outside }
         Exit(fcNoCollision);
       end else
       begin
        if not (
           CheckOutsideCorner(0, 0, 1) or
           CheckOutsideCorner(0, 1, 0) or
           CheckOutsideCorner(0, 1, 1) or
           CheckOutsideCorner(1, 0, 0) or
           CheckOutsideCorner(1, 0, 1) or
           CheckOutsideCorner(1, 1, 0) or
           CheckOutsideCorner(1, 1, 1) ) then
         { All 8 corners inside }
         Inc(InsidePlanesCount);
       end;
      end;

      if InsidePlanesCount = 6 then
        Result := fcInsideFrustum else
        Result := fcSomeCollisionPossible;
    end;
  end;

  function OldFrustumBox3DCollisionPossibleSimple(
    const Frustum: TFrustum;
    const Box: TBox3D): boolean;

  { Implementation is obviously based on
    FrustumBox3DCollisionPossible above, see there for more comments. }

  var
    fp: TFrustumPlane;
    FrustumMultiplyBox: TBox3D;

    function CheckOutsideCorner(const XIndex, YIndex, ZIndex: Cardinal): boolean;
    begin
     Result :=
       { Planes[fp].X * Box[XIndex].X +
         Planes[fp].Y * Box[YIndex].Y +
         Planes[fp].Z * Box[ZIndex].Z +
         optimized version : }
       FrustumMultiplyBox.Data[XIndex].X +
       FrustumMultiplyBox.Data[YIndex].Y +
       FrustumMultiplyBox.Data[ZIndex].Z +
       Frustum.Planes[fp][3] < 0;
    end;

  var
    LastPlane: TFrustumPlane;
  begin
    with Frustum do
    begin
      LastPlane := High(FP);
      AssertTrue(LastPlane = fpFar);

      { If the frustum has far plane in infinity, then ignore this plane. }
      if ZFarInfinity then
        LastPlane := Pred(LastPlane);

      for fp := Low(fp) to LastPlane do
      begin
        { This way I need 6 multiplications instead of 8*3=24 }
        FrustumMultiplyBox.Data[0].X := Planes[fp].X * Box.Data[0].X;
        FrustumMultiplyBox.Data[0].Y := Planes[fp].Y * Box.Data[0].Y;
        FrustumMultiplyBox.Data[0].Z := Planes[fp].Z * Box.Data[0].Z;
        FrustumMultiplyBox.Data[1].X := Planes[fp].X * Box.Data[1].X;
        FrustumMultiplyBox.Data[1].Y := Planes[fp].Y * Box.Data[1].Y;
        FrustumMultiplyBox.Data[1].Z := Planes[fp].Z * Box.Data[1].Z;

        if CheckOutsideCorner(0, 0, 0) and
           CheckOutsideCorner(0, 0, 1) and
           CheckOutsideCorner(0, 1, 0) and
           CheckOutsideCorner(0, 1, 1) and
           CheckOutsideCorner(1, 0, 0) and
           CheckOutsideCorner(1, 0, 1) and
           CheckOutsideCorner(1, 1, 0) and
           CheckOutsideCorner(1, 1, 1) then
          Exit(false);
      end;

      Result := true;
    end;
  end;

const
  Tests = {$ifdef WRITELN_TESTS} 1000000 {$else} 1000 {$endif};
var
  TestCases: array of record
    Frustum: TFrustum;
    Box: TBox3D;
    Result1: TFrustumCollisionPossible;
    Result2: boolean;
  end;
  I: Integer;
  NoOutsideResults: Cardinal;
begin
  SetLength(TestCases, Tests);

  for I := 0 to Tests - 1 do
    with TestCases[I] do
    begin
      Frustum := RandomFrustum(I > Tests div 2);
      Box := RandomBox;
    end;

  {$ifdef WRITELN_TESTS} ProcessTimerBegin; {$endif}
  for I := 0 to Tests - 1 do
    with TestCases[I] do
    begin
      Result1 := OldFrustumBox3DCollisionPossible(Frustum, Box);
    end;
  {$ifdef WRITELN_TESTS}
  Writeln('Old TFrustum.Box3DCollisionPossible: ', ProcessTimerEnd);
  {$endif}

  {$ifdef WRITELN_TESTS} ProcessTimerBegin; {$endif}
  for I := 0 to Tests - 1 do
    with TestCases[I] do
    begin
      AssertTrue(Result1 = Frustum.Box3DCollisionPossible(Box));
    end;
  {$ifdef WRITELN_TESTS}
  Writeln('New TFrustum.Box3DCollisionPossible: ', ProcessTimerEnd);
  {$endif}

  {$ifdef WRITELN_TESTS} ProcessTimerBegin; {$endif}
  for I := 0 to Tests - 1 do
    with TestCases[I] do
    begin
      Result2 := OldFrustumBox3DCollisionPossibleSimple(Frustum, Box);
    end;
  {$ifdef WRITELN_TESTS}
  Writeln('Old TFrustum.Box3DCollisionPossibleSimple: ', ProcessTimerEnd);
  {$endif}

  {$ifdef WRITELN_TESTS} ProcessTimerBegin; {$endif}
  for I := 0 to Tests - 1 do
    with TestCases[I] do
    begin
      AssertTrue(Result2 = Frustum.Box3DCollisionPossibleSimple(Box));
    end;
  {$ifdef WRITELN_TESTS}
  Writeln('New TFrustum.Box3DCollisionPossibleSimple: ', ProcessTimerEnd);
  {$endif}

  {$ifdef WRITELN_TESTS}

  NoOutsideResults := 0;

  for I := 0 to Tests - 1 do
    with TestCases[I] do
      if Result1 <> fcNoCollision then
        Inc(NoOutsideResults);

  { How much the random data resembles real-life data, in real-life
    we may get something significant like 1/6 }
  Writeln('Ratio of non-outside results: ', (NoOutsideResults/Tests):1:10);

  {$endif}
end;

procedure TTestCastleFrustum.TestTransformFrustum;

  {$define TEST_FRUSTUM_TRANSFORM_SPEED}
  {$ifdef TEST_FRUSTUM_TRANSFORM_SPEED}
  procedure DoTestSpeed;
  const
    TestsCount = 1000 * 1000;
  var
    Frustum1{, Frustum2, Frustum3}: TFrustum;
    M, MInverse: TMatrix4;
    T: TTimerResult;
    I: Integer;
  begin
    Frustum1.Init(
      PerspectiveProjectionMatrixDeg(60, 1, 10, ZFarInfinity),
      LookDirMatrix(
        Vector3(10, 10, 10) { eye position },
        Vector3(1, 0, 0) { look direction },
        Vector3(0, 0, 1) { up vector } ));

    M := TMatrix4.Identity;
    MInverse := TMatrix4.Identity;
    TransformMatricesMult(M, MInverse,
      Vector3(1, 2, 3),
      Vector4(4, 5, 6, 7),
      Vector3(8, 9, 10),
      Vector4(11, 12, 13, 14),
      Vector3(15, 16, 17));

    T := Timer;
    for I := 1 to TestsCount do
      Frustum1.TransformByInverse(MInverse);
    WritelnLog('Time of TFrustum.TransformByInverse: %f', [T.ElapsedTime]);

    T := Timer;
    for I := 1 to TestsCount do
      Frustum1.Transform(M);
    WritelnLog('Time of TFrustum.Transform: %f', [T.ElapsedTime]);
  end;
  {$endif}

var
  Frustum1{, Frustum2, Frustum3}: TFrustum;
  M, MInverse: TMatrix4;
begin
  Frustum1.Init(
    PerspectiveProjectionMatrixDeg(60, 1, 10, ZFarInfinity),
    LookDirMatrix(
      Vector3(10, 10, 10) { eye position },
      Vector3(1, 0, 0) { look direction },
      Vector3(0, 0, 1) { up vector } ));

  M := TMatrix4.Identity;
  MInverse := TMatrix4.Identity;

  AssertFrustumEquals(Frustum1, Frustum1.Transform(M));
  AssertFrustumEquals(Frustum1, Frustum1.TransformByInverse(MInverse));

  TransformMatricesMult(M, MInverse,
    Vector3(0, 0, 0),
    Vector4(0, 0, 0, 0),
    Vector3(1, 1, 1),
    Vector4(0, 0, 0, 0),
    Vector3(15, 16, 17));
  AssertFrustumEquals(Frustum1.TransformByInverse(MInverse), Frustum1.Transform(M));

  M := TMatrix4.Identity;
  MInverse := TMatrix4.Identity;
  TransformMatricesMult(M, MInverse,
    Vector3(1, 2, 3),
    Vector4(4, 5, 6, 7),
    Vector3(1, 1, 1),
    Vector4(0, 0, 0, 0),
    Vector3(15, 16, 17));
  AssertFrustumEquals(Frustum1.TransformByInverse(MInverse), Frustum1.Transform(M));

  M := TMatrix4.Identity;
  MInverse := TMatrix4.Identity;
  TransformMatricesMult(M, MInverse,
    Vector3(1, 2, 3),
    Vector4(4, 5, 6, 7),
    Vector3(10, 10, 10),
    Vector4(0, 0, 0, 0),
    Vector3(15, 16, 17));
  AssertFrustumEquals(Frustum1.TransformByInverse(MInverse), Frustum1.Transform(M));

  M := TMatrix4.Identity;
  MInverse := TMatrix4.Identity;
  TransformMatricesMult(M, MInverse,
    Vector3(1, 2, 3),
    Vector4(4, 5, 6, 7),
    Vector3(10, 20, 30),
    Vector4(0, 0, 0, 0),
    Vector3(15, 16, 17));
  // when using non-uniform scaling, we need larger epsilon to pass
  AssertFrustumEquals(Frustum1.TransformByInverse(MInverse), Frustum1.Transform(M), 0.05);

  M := TMatrix4.Identity;
  MInverse := TMatrix4.Identity;
  TransformMatricesMult(M, MInverse,
    Vector3(1, 2, 3),
    Vector4(4, 5, 6, 7),
    Vector3(8, 9, 10),
    Vector4(11, 12, 13, 14),
    Vector3(15, 16, 17));
  // when using non-uniform scaling, we need larger epsilon to pass
  AssertFrustumEquals(Frustum1.TransformByInverse(MInverse), Frustum1.Transform(M), 0.05);

  {$ifdef TEST_FRUSTUM_TRANSFORM_SPEED}
  DoTestSpeed;
  {$endif}
end;

initialization
  RegisterTest(TTestCastleFrustum);
end.
