﻿{
  Copyright 2022-2023 Andrzej Kilijański, Dean Zobec, Michael Van Canneyt, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Main view, where most of the application logic takes place. }
unit GameViewMain;

interface

uses Classes,
  CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleControls, CastleKeysMouse, CastleTester;

type
  { Main view, where most of the application logic takes place. }
  TViewMain = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelMessage: TCastleLabel;
    LabelCurrentTest: TCastleLabel;
    LabelTestPassed: TCastleLabel;
    LabelTestFailed: TCastleLabel;
    LabelFailedTests: TCastleLabel;
    LabelTestsCount: TCastleLabel;
    CheckboxStopOnFail: TCastleCheckbox;
    ButtonStartTests: TCastleButton;
    ButtonStopTests: TCastleButton;
    ButtonSelectTests: TCastleButton;
  private
    Tester: TCastleTester;
    RunTests: Boolean;

    procedure ClickStartTests(Sender: TObject);
    procedure ClickStopTests(Sender: TObject);

    procedure TestPassedCountChanged(const TestCount: Integer);
    procedure TestFailedCountChanged(const TestCount: Integer);
    procedure EnabledTestCountChanged(Sender: TObject);
    procedure TestExecuted(const AName: String);
    procedure TestFailed(const TestName, Msg: String);
    procedure LogFailure(const AMessage: String);

    procedure StartTesting;
    procedure StopTesting(const AMessage: String;
      const Exception: Boolean = false);

  public
    { Can be set before Start. }
    FilterTests: String;
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Update(const SecondsPassed: Single;
      var HandleInput: Boolean); override;
  end;

var
  ViewMain: TViewMain;

implementation

uses SysUtils,
  CastleColors, CastleUtils, CastleParameters,

  { Testing (mainly) things inside Pascal standard library, not CGE }
  TestCompiler,
  TestSysUtils,
  {$ifdef FPC}TestFGL,{$endif}
  TestGenericsCollections,
  {$ifdef FPC}TestOldFPCBugs,{$endif}
  {$ifdef FPC}TestFPImage,{$endif}
  //TestToolFpcVersion,

  { Testing CGE units }
  TestCastleUtils,
  TestCastleRectangles,
  TestCastleFindFiles,
  TestCastleFilesUtils,
  TestCastleUtilsLists,
  TestCastleClassUtils,
  TestCastleVectors,
  TestCastleTriangles,
  TestCastleColors,
  TestCastleQuaternions,
  TestCastleRenderOptions,
  TestCastleKeysMouse,
  TestCastleImages,
  TestCastleInternalDataCompression,
  TestCastleImagesDraw,
  TestCastleBoxes,
  TestCastleFrustum,
  TestCastleInternalGLShadowVolumes,
  TestCastleFonts,
  TestCastleTransform,
  TestCastleParameters,
  TestCastleUIControls,
  TestCastleCameras,
  TestX3DFields,
  TestX3DNodes,
  TestX3DNodesOptimizedProxy,
  TestX3DNodesNurbs,
  TestCastleScene,
  TestCastleSceneCore,
  TestCastleSceneManager,
  TestCastleVideos,
  TestCastleSpaceFillingCurves,
  TestCastleStringUtils,
  TestCastleScript,
  TestCastleScriptVectors,
  TestCastleCubeMaps,
  TestCastleGLVersion,
  TestCastleCompositeImage,
  TestCastleTriangulate,
  TestCastleGame,
  TestCastleUriUtils,
  TestCastleXmlUtils,
  TestCastleCurves,
  TestCastleTimeUtils,
  TestCastleControls,
  TestCastleSoundEngine,
  TestCastleComponentSerialize,
  TestCastleDesignComponents,
  TestX3DLoadInternalUtils,
  TestCastleLevels,
  TestCastleDownload,
  TestCastleUnicode,
  TestCastleResources,
  TestX3DLoadGltf,
  TestCastleTiledMap,
  TestCastleInternalAutoGenerated,
  TestCastleLocalizationGetText,
  TestCastleViewport,
  TestCastleInternalRttiUtils,
  TestCastleShapes,
  TestCastleInternalDelphiUtils

  {$ifndef NO_WINDOW_SYSTEM},
  TestCastleWindow,
  TestCastleOpeningAndRendering3D,
  TestCastleWindowOpen
  {$endif}

  { Stuff requiring Lazarus LCL. }
  // {$ifdef FPC}TestCastleLCLUtils{$endif}
  ;

{ Handle --filter command-line option.
  This is a callback for Parameters.Parse. }
procedure OptionProc(OptionNum: Integer; HasArgument: boolean;
  const Argument: string; const SeparateArgs: TSeparateArgs; Data: Pointer);
var
  View: TViewMain;
begin
  View := TViewMain(Data);
  case OptionNum of
    0: View.FilterTests := Argument;
    else raise EInternalError.Create('OptionProc: OptionNum = ' + IntToStr(OptionNum));
  end;
end;

{ TViewMain ----------------------------------------------------------------- }

procedure TViewMain.TestFailed(const TestName, Msg: String);
begin
  LogFailure(TestName + ': ' + Msg);
end;

procedure TViewMain.ClickStartTests(Sender: TObject);
begin
  Tester.StopOnFirstFail := CheckboxStopOnFail.Checked;
  Tester.PrepareTestListToRun;
  StartTesting;
end;

procedure TViewMain.ClickStopTests(Sender: TObject);
begin
  StopTesting('Testing aborted by user', false);
end;

constructor TViewMain.Create(AOwner: TComponent);
const
  Options: array [0..0] of TOption = (
    (Short:'f'; Long:'filter'; Argument: oaRequired)
  );
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
  Parameters.Parse(Options, @OptionProc, Self, true);
end;

procedure TViewMain.EnabledTestCountChanged(Sender: TObject);
begin
  LabelTestsCount.Caption := Format('Tests: %d / %d', [
    Tester.EnabledTestCount,
    Tester.TestsCount
  ]);
end;

procedure TViewMain.LogFailure(const AMessage: String);
begin
  if LabelFailedTests.Caption = '' then
    LabelFailedTests.Caption :=  AMessage
  else
    LabelFailedTests.Caption := LabelFailedTests.Caption + NL + AMessage;
end;

procedure TViewMain.Start;
begin
  inherited;

  ButtonStartTests.OnClick := {$ifdef FPC}@{$endif}ClickStartTests;

  ButtonStopTests.OnClick := {$ifdef FPC}@{$endif}ClickStopTests;
  ButtonStopTests.Enabled := false;

  ButtonSelectTests.Enabled := true;
  ButtonSelectTests.Exists := false; // TODO: ButtonSelectTests functionality not implemented yet

  { Make sure the tests are not running }
  RunTests := false;

  Tester := TCastleTester.Create(FreeAtStop);
  { We can just set values in Update but I think callbacks interface is more
    flexible in a variety of applications }
  Tester.NotifyTestPassedChanged := {$ifdef FPC}@{$endif}TestPassedCountChanged;
  Tester.NotifyTestFailedChanged := {$ifdef FPC}@{$endif}TestFailedCountChanged;
  Tester.NotifyEnabledTestCountChanged := {$ifdef FPC}@{$endif}EnabledTestCountChanged;
  Tester.NotifyTestCaseExecuted := {$ifdef FPC}@{$endif}TestExecuted;
  Tester.NotifyTestFail := {$ifdef FPC}@{$endif}TestFailed;


  { You can add all Registered tests by calling AddRegisteredTestCases }
  Tester.AddRegisteredTestCases;

  { Or add only one test case by code eg. }
  (*
  Tester.AddTestCase(TTestURIUtils.Create);
  Tester.AddTestCase(TTestCastleBoxes.Create);
  Tester.AddTestCase(TTestCameras.Create);
  Tester.AddTestCase(TTestCastleClassUtils.Create);
  Tester.AddTestCase(TTestCastleColors.Create);
  Tester.AddTestCase(TTestCastleComponentSerialize.Create); *)

  { Scans all tests }
  Tester.Scan;
  if FilterTests <> '' then
    Tester.EnableFilter(FilterTests);
  { First prepare to count acctualy selected tests }
  Tester.PrepareTestListToRun;
end;

procedure TViewMain.StartTesting;
begin
  RunTests := true;
  LabelMessage.Caption := 'Processing...';
  LabelMessage.Color := HexToColor('00CE00');
  ButtonStartTests.Enabled := false;
  ButtonStopTests.Enabled := true;
  ButtonSelectTests.Enabled := false;
end;

procedure TViewMain.StopTesting(const AMessage: String; const Exception: Boolean = false);
begin
  RunTests := false;

  LabelMessage.Caption := AMessage;

  { If some test ends with unhandled exception we want it on our error list }
  if Exception then
    LogFailure(AMessage);

  if (Tester.TestFailedCount > 0) or (Exception) then
    LabelMessage.Color := HexToColor('C60D0D')
  else
    LabelMessage.Color := HexToColor('00CE00');

  ButtonStartTests.Enabled := true;
  ButtonStopTests.Enabled := false;
  ButtonSelectTests.Enabled := true;
end;

procedure TViewMain.TestExecuted(const AName: String);
begin
  LabelCurrentTest.Caption := AName;
end;

procedure TViewMain.TestFailedCountChanged(const TestCount: Integer);
begin
  LabelTestFailed.Caption := IntToStr(TestCount);
end;

procedure TViewMain.TestPassedCountChanged(const TestCount: Integer);
begin
  LabelTestPassed.Caption := IntToStr(TestCount);
end;

procedure TViewMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  if RunTests then
  begin
    if Tester.IsNextTestToRun then
    begin
      try
        TEster.RunNextTest;
      except
        on E:Exception do
        begin
          { In case of UI application we don't want any unhandled exceptions }
          StopTesting('Unhandled exception: ' + E.Message, true);
        end;
      end;
    end else
    begin
      StopTesting('Testing finished');
    end;
  end;

  inherited;
end;

end.
