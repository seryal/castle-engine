// -*- compile-command: "./test_single_testcase.sh TTestCastleInternalRttiUtils" -*-
{
  Copyright 2009-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test CastleInternalRttiUtils unit. }
unit TestCastleInternalRttiUtils;

interface

uses {$ifndef CASTLE_TESTER}FpcUnit, TestUtils, TestRegistry{$else}CastleTester{$endif};

type
  TTestCastleInternalRttiUtils = class({$ifndef CASTLE_TESTER}TTestCase{$else}TCastleTestCase{$endif})
  published
    procedure TestPropertyHasDefaultValue;
  end;

implementation

uses SysUtils, Math, Classes, TypInfo,
  CastleVectors, CastleTransform, CastleInternalRttiUtils;

procedure TTestCastleInternalRttiUtils.TestPropertyHasDefaultValue;
var
  Cam: TCastleCamera;
begin
  Cam := TCastleCamera.Create(nil);
  try
    Cam.ProjectionNear := 10;
    AssertTrue(PropertyHasDefaultValue(Cam, GetPropInfo(Cam, 'ProjectionType')));
    AssertFalse(PropertyHasDefaultValue(Cam, GetPropInfo(Cam, 'ProjectionNear')));
    AssertTrue(PropertyHasDefaultValue(Cam, GetPropInfo(Cam, 'ProjectionFar')));

    AssertTrue(Cam.TranslationPersistent.HasDefaultValue);
    Cam.Translation := Vector3(10, 0, 0);
    AssertFalse(Cam.TranslationPersistent.HasDefaultValue);

    { vector components have no defaults (not even 0 is considered default),
      they are decided using IsStoredProp. }
    AssertFalse(PropertyHasDefaultValue(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'X')));
    AssertFalse(PropertyHasDefaultValue(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'Y')));
    AssertFalse(PropertyHasDefaultValue(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'Z')));

    AssertTrue(IsStoredProp(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'X')));
    AssertFalse(IsStoredProp(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'Y')));
    AssertFalse(IsStoredProp(Cam.TranslationPersistent, GetPropInfo(Cam.TranslationPersistent, 'Z')));
  finally FreeAndNil(Cam) end;
end;

initialization
  RegisterTest(TTestCastleInternalRttiUtils);
end.
