{ -*- compile-command: "./castleengine_compile.sh" -*- }
{
  Copyright 2013-2024 Jan Adamec, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ The castleengine library main source code.
  This compiles to castleengine.dll / libcastleengine.so / libcastleengine.dylib.

  Development notes:

  Adapted from Jonas Maebe's example project :
  http://users.elis.ugent.be/~jmaebe/fpc/FPC_Objective-C_Cocoa.tbz
  http://julien.marcel.free.fr/ObjP_Part7.html

  To make c-compatible (and Xcode-compatible) libraries, you must :
  1- use c-types arguments
  2- add a "cdecl" declaration after your functions declarations
  3- export your functions

  See FPC CTypes unit (source rtl/unix/ctypes.inc) for a full list of c-types.
}

library castleengine;

uses CTypes, Math, SysUtils, CastleUtils,
  Classes, CastleKeysMouse, CastleCameras, CastleVectors, CastleGLUtils, CastleGLVersion,
  CastleImages, CastleSceneCore, CastleUIControls, X3DNodes, X3DFields, CastleLog,
  CastleBoxes, CastleControls, CastleInputs, CastleApplicationProperties,
  CastleWindow, CastleViewport, CastleScene, CastleTransform;

type
  TCrosshairManager = class(TObject)
  public
    CrosshairCtl: TCastleCrosshair;
    CrosshairActive: boolean;

    constructor Create;
    destructor Destroy; override;

    procedure UpdateCrosshairImage;
    procedure OnPointingDeviceSensorsChange(Sender: TObject);
  end;

var
  Window: TCastleWindow;
  { Using TCastleAutoNavigationViewport in this case is justified,
    it is the most straightforward solution to make viewport navigation
    follow X3D navigation. }
  {$warnings off}
  Viewport: TCastleAutoNavigationViewport;
  {$warnings on}
  MainScene: TCastleScene; //< Always equal to Viewport.Items.MainScene
  PreviousNavigationType: TNavigationType;
  TouchNavigation: TCastleTouchNavigation;
  Crosshair: TCrosshairManager;

{ Check that CGE_Open was called, and at least Window and Viewport are created. }
function CGE_VerifyWindow(const FromFunc: string): boolean;
begin
  Result :=
    (Window <> nil) and
    (Viewport <> nil);
  if not Result then
    WarningWrite(FromFunc + ' : CGE window not initialized (CGE_Open not called)');
end;

{ Check that CGE_LoadSceneFromFile was called,
  and at least Window and Viewport and MainScene are created. }
function CGE_VerifyScene(const FromFunc: string): boolean;
begin
  Result :=
    (Window <> nil) and
    (Viewport <> nil) and
    (MainScene <> nil);
  {$warnings off} // using Viewport.Items.MainScene is this case is justified
  Assert((not Result) or (Viewport.Items.MainScene = MainScene));
  if not Result then
    WarningWrite(FromFunc + ': CGE scene not initialized (CGE_LoadSceneFromFile not called)');
end;

procedure CGE_Initialize(ApplicationConfigDirectory: PChar); cdecl;
begin
  CGEApp_Initialize(ApplicationConfigDirectory);
end;

procedure CGE_Finalize(); cdecl;
begin
  CGEApp_Finalize();
end;

procedure CGE_Open(flags: cUInt32; InitialWidth, InitialHeight, Dpi: cUInt32); cdecl;
begin
  try
    if (flags and 1 {ecgeofSaveMemory}) > 0 then
    begin
      DefaultTriangulationSlices := 16;
      DefaultTriangulationStacks := 16;
    end;
    if (flags and 2 {ecgeofLog}) > 0 then
      InitializeLog;

    Window := TCastleWindow.Create(nil);
    Application.MainWindow := Window;

    Viewport := TCastleAutoNavigationViewport.Create(Window);
    Viewport.FullSize := true;
    { AutoCamera is necessary for Viewport.Camera to follow X3D file camera,
      not only at initialization (this is done by AssignDefaultCamera) but also
      when new viewpoint node is bound using X3D events or
      TCastleSceneCore.MoveToViewpoint call. }
    Viewport.AutoCamera := true;
    { AutoNavigation is necessary for navigation to follow routes in X3D file.
      For example when changing navigation by X3D events in
      demo-models/navigation/navigation_info_bind.x3dv , to make it affect actual
      CGE navigation. }
    Viewport.AutoNavigation := true;
    Window.Controls.InsertFront(Viewport);

    TouchNavigation := TCastleTouchNavigation.Create(nil);
    TouchNavigation.FullSize := true;
    TouchNavigation.Viewport := Viewport;
    Viewport.InsertFront(TouchNavigation);

    PreviousNavigationType := Viewport.NavigationType;

    CGEApp_Open(InitialWidth, InitialHeight, 0, Dpi);

    Crosshair := TCrosshairManager.Create;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Open: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Close(QuitWhenNoOpenWindows: CBool); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_Close') then Exit;

    if MainScene <> nil then
      MainScene.OnPointingDeviceSensorsChange := nil;
    FreeAndNil(Crosshair);

    CGEApp_Close(QuitWhenNoOpenWindows);
    FreeAndNil(Window);
    MainScene := nil;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Close: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetOpenGLInformation(szBuffer: pchar; nBufSize: cInt32); cdecl;
var
  sText: string;
begin
  try
    sText := GLInformationString;
    StrPLCopy(szBuffer, sText, nBufSize-1);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetOpenGLInformation: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Resize(uiViewWidth, uiViewHeight: cUInt32); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_Resize') then exit;
    CGEApp_Resize(uiViewWidth, uiViewHeight, 0);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Resize: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Render; cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_Render') then exit;
    CGEApp_Render;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Render: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SaveScreenshotToFile(szFile: pcchar); cdecl;
var
  Image: TRGBImage;
begin
  try
    if not CGE_VerifyWindow('CGE_SaveScreenshotToFile') then exit;

    // hide touch controls
    TouchNavigation.Exists := false;

    // make screenshot
    Image := Window.SaveScreen;
    try
      SaveImage(Image, StrPas(PChar(szFile)));
    finally FreeAndNil(Image) end;

    // restore hidden controls
    TouchNavigation.Exists := true;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SaveScreenshotToFile: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetLibraryCallbackProc(aProc: TLibraryCallbackProc); cdecl;
begin
  if Window = nil then exit;
  CGEApp_SetLibraryCallbackProc(aProc);
end;

procedure CGE_Update; cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_Update') then exit;

    { Call LibraryCallbackProc(ecgelibNavigationTypeChanged,...) when necessary.
      For this, we just query the Viewport.NavigationType every frame. }
    if PreviousNavigationType <> Viewport.NavigationType then
    begin
      PreviousNavigationType := Viewport.NavigationType;
      if Assigned(LibraryCallbackProc) then
      begin
        case Viewport.NavigationType of
          ntWalk     : LibraryCallbackProc(ecgelibNavigationTypeChanged, ecgenavWalk     , 0, nil);
          ntFly      : LibraryCallbackProc(ecgelibNavigationTypeChanged, ecgenavFly      , 0, nil);
          ntExamine  : LibraryCallbackProc(ecgelibNavigationTypeChanged, ecgenavExamine  , 0, nil);
          ntTurntable: LibraryCallbackProc(ecgelibNavigationTypeChanged, ecgenavTurntable, 0, nil);
          ntNone     : LibraryCallbackProc(ecgelibNavigationTypeChanged, ecgenavNone     , 0, nil);
          // nt2D: TODO
          else WritelnWarning('Window', 'Current NavigationType cannot be expressed as enum for ecgelibNavigationTypeChanged');
        end;
      end;
    end;

    { Set Cursor = mcHand when we're over or keeping active
      some pointing-device sensors. The engine doesn't do it automatically
      (after https://github.com/castle-engine/castle-engine/commit/5b2810d9ef2fd0f851bc50b0a6aa7b414381dd2c )
      but it makes total sense for X3D viewers with single viewport and single
      TCastleScene. }
    if (MainScene <> nil) and
      ( ( (MainScene.PointingDeviceSensors <> nil) and
          (MainScene.PointingDeviceSensors.EnabledCount <> 0)
        ) or
        (MainScene.PointingDeviceActiveSensors.Count <> 0)
      ) then
      Viewport.Cursor := mcHand
    else
      Viewport.Cursor := mcDefault;

    CGEApp_Update;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Update: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseDown(X, Y: CInt32; bLeftBtn: cBool; FingerIndex: CInt32); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_MouseDown') then exit;
    CGEApp_MouseDown(X, Y, bLeftBtn, FingerIndex);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseDown: ' + ExceptMessage(E));
  end;
end;

procedure CGE_Motion(X, Y: CInt32; FingerIndex: CInt32); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_Motion') then exit;
    CGEApp_Motion(X, Y, FingerIndex);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_Motion: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseUp(X, Y: cInt32; bLeftBtn: cBool;
  FingerIndex: CInt32; TrackReleased: cBool); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_MouseUp') then exit;
    CGEApp_MouseUp(X, Y, bLeftBtn, FingerIndex, TrackReleased);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseUp: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MouseWheel(zDelta: cFloat; bVertical: cBool); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_MouseWheel') then exit;
    // TODO: no corresponding CGEApp callback, as not implemented in iOS code
    // (in ios_tested not used anyway, because USE_GESTURE_RECOGNIZERS
    // undefined, and also --- pinch is not really a mouse wheel)
    Window.LibraryMouseWheel(zDelta/120, bVertical);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MouseWheel: ' + ExceptMessage(E));
  end;
end;

procedure CGE_KeyDown(eKey: CInt32); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_KeyDown') then exit;
    CGEApp_KeyDown(eKey);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_KeyDown: ' + ExceptMessage(E));
  end;
end;

procedure CGE_KeyUp(eKey: CInt32); cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_KeyUp') then exit;
    CGEApp_KeyUp(eKey);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_KeyUp: ' + ExceptMessage(E));
  end;
end;

procedure CGE_LoadSceneFromFile(szFile: pcchar); cdecl;
begin
  if Window = nil then exit;
  try
    FreeAndNil(MainScene); // if any previous scene exists, remove it

    MainScene := TCastleScene.Create(Window);
    MainScene.Load(StrPas(PChar(szFile)));
    MainScene.PreciseCollisions := true;
    MainScene.ProcessEvents := true;
    MainScene.ListenPressRelease := true; // necessary to pass keys to X3D sensors
    Viewport.Items.Add(MainScene);
    { While CGE deprecated Items.MainScene, it is justified and recommended
      solution in this case, to make MainScene affect various things
      (skybox, fog, camera, navigation etc.). }
    {$warnings off}
    Viewport.Items.MainScene := MainScene;
    {$warnings on}

    Viewport.AssignDefaultCamera;
    Viewport.AssignDefaultNavigation;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_LoadSceneFromFile: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SaveSceneToFile(szFile: pcchar); cdecl;
begin
  if not CGE_VerifyScene('CGE_SaveSceneToFile') then
    exit;
  try
    MainScene.Save(StrPas(PChar(szFile)));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SaveSceneToFile: ' + ExceptMessage(E));
  end;
end;

function CGE_GetViewpointsCount(): cInt32; cdecl;
begin
  try
    if not CGE_VerifyScene('CGE_GetViewpointsCount') then
    begin
      Result := 0;
      exit;
    end;

    Result := MainScene.ViewpointsCount;
  except
    on E: TObject do
    begin
      WritelnLog('Window', 'CGE_GetViewpointsCount: ' + ExceptMessage(E));
      Result := 0;
    end;
  end;
end;

procedure CGE_GetViewpointName(iViewpointIdx: cInt32; szName: pchar; nBufSize: cInt32); cdecl;
var
  sName: string;
begin
  try
    if not CGE_VerifyScene('CGE_GetViewpointName') then exit;

    sName := MainScene.GetViewpointName(iViewpointIdx);
    StrPLCopy(szName, sName, nBufSize-1);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetViewpointName: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MoveToViewpoint(iViewpointIdx: cInt32; bAnimated: cBool); cdecl;
begin
  try
    if not CGE_VerifyScene('CGE_MoveToViewpoint') then exit;

    MainScene.MoveToViewpoint(iViewpointIdx, bAnimated);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MoveToViewpoint: ' + ExceptMessage(E));
  end;
end;

procedure CGE_AddViewpointFromCurrentView(szName: pcchar); cdecl;
begin
  try
    if not CGE_VerifyScene('CGE_AddViewpointFromCurrentView') then exit;

    if Viewport.Navigation <> nil then
      MainScene.AddViewpointFromNavigation(
        Viewport.Navigation, StrPas(PChar(szName)));
  except
    on E: TObject do WritelnWarning('Window', 'CGE_AddViewpointFromCurrentView: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetBoundingBox(pfXMin, pfXMax, pfYMin, pfYMax, pfZMin, pfZMax: pcfloat); cdecl;
var
  BBox: TBox3D;
begin
  try
    if not CGE_VerifyScene('CGE_GetBoundingBox') then exit;

    BBox := MainScene.BoundingBox;
    pfXMin^ := BBox.Data[0].X; pfXMax^ := BBox.Data[1].X;
    pfYMin^ := BBox.Data[0].Y; pfYMax^ := BBox.Data[1].Y;
    pfZMin^ := BBox.Data[0].Z; pfZMax^ := BBox.Data[1].Z;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetBoundingBox: ' + ExceptMessage(E));
  end;
end;

procedure CGE_GetViewCoords(pfPosX, pfPosY, pfPosZ, pfDirX, pfDirY, pfDirZ,
                            pfUpX, pfUpY, pfUpZ, pfGravX, pfGravY, pfGravZ: pcfloat); cdecl;
var
  Pos, Dir, Up, GravityUp: TVector3;
begin
  try
    if not CGE_VerifyWindow('CGE_GetViewCoords') then exit;

    Viewport.Camera.GetWorldView(Pos, Dir, Up);
    GravityUp := Viewport.Camera.GravityUp;
    pfPosX^ := Pos.X; pfPosY^ := Pos.Y; pfPosZ^ := Pos.Z;
    pfDirX^ := Dir.X; pfDirY^ := Dir.Y; pfDirZ^ := Dir.Z;
    pfUpX^ := Up.X; pfUpY^ := Up.Y; pfUpZ^ := Up.Z;
    pfGravX^ := GravityUp.X; pfGravY^ := GravityUp.Y; pfGravZ^ := GravityUp.Z;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetViewCoords: ' + ExceptMessage(E));
  end;
end;

procedure CGE_MoveViewToCoords(fPosX, fPosY, fPosZ, fDirX, fDirY, fDirZ,
                               fUpX, fUpY, fUpZ, fGravX, fGravY, fGravZ: cFloat;
                               bAnimated: cBool); cdecl;
var
  Pos, Dir, Up, GravityUp: TVector3;
begin
  try
    if not CGE_VerifyWindow('CGE_MoveViewToCoords') then exit;

    Pos.X := fPosX; Pos.Y := fPosY; Pos.Z := fPosZ;
    Dir.X := fDirX; Dir.Y := fDirY; Dir.Z := fDirZ;
    Up.X := fUpX; Up.Y := fUpY; Up.Z := fUpZ;
    GravityUp.X := fGravX; GravityUp.Y := fGravY; GravityUp.Z := fGravZ;
    if bAnimated then
      Viewport.Camera.AnimateTo(Pos, Dir, Up, 0.5)
    else
      Viewport.Camera.SetWorldView(Pos, Dir, Up);
    Viewport.Camera.GravityUp := GravityUp;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_MoveViewToCoords: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNavigationInputShortcut(eInput, eKey1, eKey2,
                               eMouseButton, eMouseWheel: cInt32); cdecl;
var
  Nav: TCastleNavigation;
  WalkNavigation: TCastleWalkNavigation;
  ExamineNavigation: TCastleExamineNavigation;
  InputShortcut: TInputShortcut;
  InKey1: TKey;
  InKey2: TKey = keyNone;
  InKeyString: String = '';
  InMouseButtonUse: boolean;
  InMouseButton: TCastleMouseButton;
  InMouseWheel: TMouseWheelDirection;
begin
  try
    if not CGE_VerifyWindow('CGE_SetCameraInputShortcut') then exit;

    InKey1 := TKey(eKey1);
    InKey2 := TKey(eKey2);
    InMouseButtonUse := (eMouseButton <> 0);
    case eMouseButton of
      0: InMouseButton := buttonLeft;
      1: InMouseButton := buttonLeft;
      2: InMouseButton := buttonMiddle;
      3: InMouseButton := buttonRight;
      4: InMouseButton := buttonExtra1;
      5: InMouseButton := buttonExtra2;
    end;
    case eMouseWheel of
      0: InMouseWheel := mwNone;
      1: InMouseWheel := mwUp;
      2: InMouseWheel := mwDown;
      3: InMouseWheel := mwLeft;
      4: InMouseWheel := mwRight;
    end;

    InputShortcut := nil;
    Nav := Viewport.Navigation;
    if Nav is TCastleWalkNavigation then
    begin
      WalkNavigation := TCastleWalkNavigation(Nav);
      case eInput of
        1: InputShortcut := WalkNavigation.Input_ZoomIn;
        2: InputShortcut := WalkNavigation.Input_ZoomOut;
        11: InputShortcut := WalkNavigation.Input_Forward;
        12: InputShortcut := WalkNavigation.Input_Backward;
        13: InputShortcut := WalkNavigation.Input_LeftRotate;
        14: InputShortcut := WalkNavigation.Input_RightRotate;
        15: InputShortcut := WalkNavigation.Input_LeftStrafe;
        16: InputShortcut := WalkNavigation.Input_RightStrafe;
        17: InputShortcut := WalkNavigation.Input_UpRotate;
        18: InputShortcut := WalkNavigation.Input_DownRotate;
        19: InputShortcut := WalkNavigation.Input_IncreasePreferredHeight;
        20: InputShortcut := WalkNavigation.Input_DecreasePreferredHeight;
        21: InputShortcut := WalkNavigation.Input_GravityUp;
        22: InputShortcut := WalkNavigation.Input_Run;
        23: InputShortcut := WalkNavigation.Input_MoveSpeedInc;
        24: InputShortcut := WalkNavigation.Input_MoveSpeedDec;
        25: InputShortcut := WalkNavigation.Input_Jump;
        26: InputShortcut := WalkNavigation.Input_Crouch;
        else raise EInternalError.CreateFmt('CGE_SetCameraInputShortcut: Invalid input type %d for walk navigation', [eInput]);
      end;
      if InputShortcut <> nil then
        InputShortcut.Assign(InKey1, InKey2, InKeyString, InMouseButtonUse, InMouseButton, InMouseWheel);
    end
    else if Nav is TCastleExamineNavigation then
    begin
      ExamineNavigation := TCastleExamineNavigation(Nav);
      case eInput of
        1: InputShortcut := ExamineNavigation.Input_ZoomIn;
        2: InputShortcut := ExamineNavigation.Input_ZoomOut;
        31: InputShortcut := ExamineNavigation.Input_Rotate;
        32: InputShortcut := ExamineNavigation.Input_Move;
        33: InputShortcut := ExamineNavigation.Input_Zoom;
        else raise EInternalError.CreateFmt('CGE_SetCameraInputShortcut: Invalid input type %d for examine navigation', [eInput]);
      end;
      if InputShortcut <> nil then
        InputShortcut.Assign(InKey1, InKey2, InKeyString, InMouseButtonUse, InMouseButton, InMouseWheel);
    end;
  except
    on E: TObject do WritelnLog('Window', 'CGE_SetCameraInputShortcut: ' + ExceptMessage(E));
  end;
end;

function CGE_GetNavigationType(): cInt32; cdecl;
begin
  try
    if not CGE_VerifyWindow('CGE_GetNavigationType') then Exit(-1);

    case Viewport.NavigationType of
      ntWalk     : Result := 0;
      ntFly      : Result := 1;
      ntExamine  : Result := 2;
      ntTurntable: Result := 3;
      ntNone     : Result := 4;
      // nt2D: TODO
      else raise EInternalError.Create('CGE_GetNavigationType: Unrecognized Viewport.NavigationType');
    end;
  except
    on E: TObject do
    begin
      WritelnLog('Window', 'CGE_GetNavigationType: ' + ExceptMessage(E));
      Result := -1;
    end;
  end;
end;

procedure CGE_SetNavigationType(NewType: cInt32); cdecl;
var
  aNavType: TNavigationType;
begin
  try
    if not CGE_VerifyWindow('CGE_SetNavigationType') then exit;

    case NewType of
      0: aNavType := ntWalk;
      1: aNavType := ntFly;
      2: aNavType := ntExamine;
      3: aNavType := ntTurntable;
      4: aNavType := ntNone;
      // TODO: aNavType := nt2D;
      else raise EInternalError.CreateFmt('CGE_SetNavigationType: Invalid navigation type %d', [NewType]);
    end;
    Viewport.NavigationType := aNavType;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNavigationType: ' + ExceptMessage(E));
  end;
end;

function cgehelper_TouchInterfaceFromConst(eMode: cInt32): TTouchInterface;
begin
  case eMode of
    0: Result := tiNone;
    1: Result := tiWalk;
    2: Result := tiWalkRotate;
    3: Result := tiFlyWalk;
    4: Result := tiPan;
    else raise EInternalError.CreateFmt('cgehelper_TouchInterfaceFromConst: Invalid touch interface mode %d', [eMode]);
  end;
end;

function cgehelper_ConstFromTouchInterface(eMode: TTouchInterface): cInt32;
begin
  Result := 0;
  case eMode of
    tiWalk: Result := 1;
    tiWalkRotate: Result := 2;
    tiFlyWalk: Result := 3;
    tiPan: Result := 4;
  end;
end;

procedure CGE_SetTouchInterface(eMode: cInt32); cdecl;
begin
  try
    TouchNavigation.TouchInterface := cgehelper_TouchInterfaceFromConst(eMode);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetTouchInterface: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetUserInterface(bAutomaticTouchInterface: cBool); cdecl;
begin
  try
    TouchNavigation.AutoTouchInterface := bAutomaticTouchInterface;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetUserInterface: ' + ExceptMessage(E));
  end;
end;

procedure CGE_IncreaseSceneTime(fTimeS: cFloat); cdecl;
var
  DummyRemoveType: TRemoveType;
begin
  try
    MainScene.IncreaseTime(fTimeS);
    DummyRemoveType := rtNone;
    Viewport.Camera.Update(fTimeS, DummyRemoveType);
  except
    on E: TObject do WritelnWarning('Window', 'CGE_IncreaseSceneTime: ' + ExceptMessage(E));
  end;
end;

function GetWalkNavigation: TCastleWalkNavigation;
var
  Nav: TCastleNavigation;
begin
  Nav := Viewport.Navigation;
  if Nav is TCastleWalkNavigation then
    Result := TCastleWalkNavigation(Nav)
  else
    Result := nil;
end;

procedure CGE_SetVariableInt(eVar: cInt32; nValue: cInt32); cdecl;
var
  WalkNavigation: TCastleWalkNavigation;
begin
  if Window = nil then exit;
  try
    case eVar of
      0: begin    // ecgevarWalkHeadBobbing
           WalkNavigation := GetWalkNavigation;
           if WalkNavigation <> nil then
           begin
             if nValue > 0 then
               WalkNavigation.HeadBobbing := TCastleWalkNavigation.DefaultHeadBobbing
             else
               WalkNavigation.HeadBobbing := 0.0;
           end;
         end;

      1: begin    // ecgevarEffectSSAO
           if Viewport.ScreenSpaceAmbientOcclusionAvailable then
             Viewport.ScreenSpaceAmbientOcclusion := (nValue > 0);
         end;

      2: begin    // ecgevarMouseLook
           WalkNavigation := GetWalkNavigation;
           if WalkNavigation <> nil then
               WalkNavigation.MouseLook := (nValue > 0);
         end;

      3: begin    // ecgevarCrossHair
           Crosshair.CrosshairCtl.Exists := (nValue > 0);
           if nValue > 0 then
           begin
             if nValue = 2 then
               Crosshair.CrosshairCtl.Shape := csCrossRect
             else
               Crosshair.CrosshairCtl.Shape := csCross;
             Crosshair.UpdateCrosshairImage;
             MainScene.OnPointingDeviceSensorsChange := @Crosshair.OnPointingDeviceSensorsChange;
           end;
         end;

      5: begin    // ecgevarWalkTouchCtl
           TouchNavigation.AutoWalkTouchInterface := cgehelper_TouchInterfaceFromConst(nValue);
         end;

      6: begin    // ecgevarScenePaused
           Viewport.Items.Paused := (nValue > 0);
         end;

      7: begin    // ecgevarAutoRedisplay
           Window.AutoRedisplay := (nValue > 0);
         end;

      8: begin    // ecgevarHeadlight
           if MainScene <> nil then
              MainScene.HeadlightOn := (nValue > 0);
         end;

      9: begin    // ecgevarOcclusionCulling
           if Viewport <> nil then
              Viewport.OcclusionCulling := (nValue > 0);
         end;

      10: begin    // ecgevarPhongShading
            if MainScene <> nil then
               MainScene.RenderOptions.PhongShading := (nValue > 0);
          end;
    end;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetVariableInt: ' + ExceptMessage(E));
  end;
end;

function CGE_GetVariableInt(eVar: cInt32): cInt32; cdecl;
var
  WalkNavigation: TCastleWalkNavigation;
begin
  Result := -1;
  if Window = nil then exit;
  try
    case eVar of
      0: begin    // ecgevarWalkHeadBobbing
           WalkNavigation := GetWalkNavigation;
           if (WalkNavigation <> nil) and (WalkNavigation.HeadBobbing > 0) then
             Result := 1
           else
             Result := 0;
         end;

      1: begin    // ecgevarEffectSSAO
           if Viewport.ScreenSpaceAmbientOcclusionAvailable and
              Viewport.ScreenSpaceAmbientOcclusion then
             Result := 1
           else
             Result := 0;
         end;

      2: begin    // ecgevarMouseLook
           WalkNavigation := GetWalkNavigation;
           if (WalkNavigation <> nil) and WalkNavigation.MouseLook then
             Result := 1
           else
             Result := 0;
         end;

      3: begin    // ecgevarCrossHair
           if not Crosshair.CrosshairCtl.Exists then
             Result := 0
           else
           if Crosshair.CrosshairCtl.Shape = csCross then
             Result := 1
           else
           if Crosshair.CrosshairCtl.Shape = csCrossRect then
             Result := 2
           else
             Result := 1;
         end;

      4: begin    // ecgevarAnimationRunning
           if Viewport.Camera.Animation then
             Result := 1
           else
             Result := 0;
         end;

      5: begin    // ecgevarWalkTouchCtl
           Result := cgehelper_ConstFromTouchInterface(TouchNavigation.AutoWalkTouchInterface);
         end;

      6: begin    // ecgevarScenePaused
           if Viewport.Items.Paused then
             Result := 1
           else
             Result := 0;
         end;

      7: begin    // ecgevarAutoRedisplay
           if Window.AutoRedisplay then
             Result := 1
           else
             Result := 0;
         end;

      8: begin    // ecgevarHeadlight
           if (MainScene <> nil) and MainScene.HeadlightOn then
             Result := 1
           else
             Result := 0;
         end;

      9: begin    // ecgevarOcclusionCulling
           if (Viewport <> nil) and Viewport.OcclusionCulling then
             Result := 1
           else
             Result := 0;
         end;

      10: begin    // ecgevarPhongShading
        if (MainScene <> nil) and MainScene.RenderOptions.PhongShading then
          Result := 1 else
          Result := 0;
      end;

      else Result := -1; // unsupported variable
    end;
  except
    on E: TObject do WritelnWarning('Window', 'CGE_GetVariableInt: ' + ExceptMessage(E));
  end;
end;

procedure CGE_SetNodeFieldValue(szNodeName, szFieldName: pcchar;
                                fVal1, fVal2, fVal3, fVal4: cFloat); cdecl;
var
  aField: TX3DField;
begin
  try
    if not CGE_VerifyScene('CGE_SetNodeFieldValue') then exit;

    // find node and field
    aField := MainScene.Field(PChar(szNodeName), PChar(szFieldName));
    if aField = nil then Exit;

    if aField is TSFVec2f then
      TSFVec2f(aField).Send(Vector2(fVal1, fVal2))
    else
    if aField is TSFVec3f then
      TSFVec3f(aField).Send(Vector3(fVal1, fVal2, fVal3))
    else
    if aField is TSFVec4f then
      TSFVec4f(aField).Send(Vector4(fVal1, fVal2, fVal3, fVal4))
    else
    if aField is TSFVec2d then
      TSFVec2d(aField).Send(Vector2Double(fVal1, fVal2))
    else
    if aField is TSFVec3d then
      TSFVec3d(aField).Send(Vector3Double(fVal1, fVal2, fVal3))
    else
    if aField is TSFVec4d then
      TSFVec4d(aField).Send(Vector4Double(fVal1, fVal2, fVal3, fVal4))
    else
    if aField is TSFFloat then
      TSFFloat(aField).Send(fVal1)
    else
    if aField is TSFDouble then
      TSFDouble(aField).Send(fVal1)
    else
    if aField is TSFLong then
      TSFLong(aField).Send(Round(fVal1))
    else
    if aField is TSFInt32 then
      TSFInt32(aField).Send(Round(fVal1))
    else
    if aField is TSFBool then
      TSFBool(aField).Send(fVal1 <> 0.0);

  except
    on E: TObject do WritelnWarning('Window', 'CGE_SetNodeFieldValue: ' + ExceptMessage(E));
  end;
end;

constructor TCrosshairManager.Create;
begin
  inherited;
  CrosshairCtl := TCastleCrosshair.Create(Window);
  CrosshairCtl.Exists := false;  // start as invisible
  Window.Controls.InsertFront(CrosshairCtl);
end;

destructor TCrosshairManager.Destroy;
begin
  Window.Controls.Remove(CrosshairCtl);
  FreeAndNil(CrosshairCtl);
  inherited;
end;

procedure TCrosshairManager.UpdateCrosshairImage;
begin
  begin
    if not CrosshairCtl.Exists then Exit;

    if CrosshairActive then
      CrosshairCtl.Shape := csCrossRect else
      CrosshairCtl.Shape := csCross;
  end;
end;

procedure TCrosshairManager.OnPointingDeviceSensorsChange(Sender: TObject);
var
  OverSensor: Boolean;
  SensorList: TPointingDeviceSensorList;
begin
  { check if the crosshair (mouse) is over any sensor }
  OverSensor := false;
  SensorList := MainScene.PointingDeviceSensors;
  if (SensorList <> nil) then
    OverSensor := (SensorList.EnabledCount>0);

  if CrosshairActive <> OverSensor then
  begin
    CrosshairActive := OverSensor;
    UpdateCrosshairImage;
  end;
end;

exports
  CGE_Initialize,
  CGE_Finalize,
  CGE_Open,
  CGE_Close,
  CGE_GetOpenGLInformation,
  CGE_Render,
  CGE_Resize,
  CGE_SetLibraryCallbackProc,
  CGE_Update,
  CGE_MouseDown,
  CGE_Motion,
  CGE_MouseUp,
  CGE_MouseWheel,
  CGE_KeyDown,
  CGE_KeyUp,
  CGE_LoadSceneFromFile,
  CGE_SaveSceneToFile,
  CGE_SetNavigationInputShortcut,
  CGE_GetNavigationType,
  CGE_SetNavigationType,
  CGE_GetViewpointsCount,
  CGE_GetViewpointName,
  CGE_MoveToViewpoint,
  CGE_AddViewpointFromCurrentView,
  CGE_GetBoundingBox,
  CGE_GetViewCoords,
  CGE_MoveViewToCoords,
  CGE_SaveScreenshotToFile,
  CGE_SetTouchInterface,
  CGE_SetUserInterface,
  CGE_IncreaseSceneTime,
  CGE_SetVariableInt,
  CGE_GetVariableInt,
  CGE_SetNodeFieldValue;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end.
