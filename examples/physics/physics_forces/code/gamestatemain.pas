{
  Copyright 2022-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Main state, where most of the application logic takes place. }
unit GameStateMain;

interface

uses Classes,
  CastleVectors, CastleUIState, CastleComponentSerialize,
  CastleUIControls, CastleControls, CastleKeysMouse, CastleScene, CastleTransform;

type
  { Main state, where most of the application logic takes place. }
  TStateMain = class(TUIState)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelFps,
      LabelAddForceAtPosition,
      LabelAddForce,
      LabelAddTorque,
      LabelApplyImpulse: TCastleLabel;
    SceneArrow: TCastleScene;
    DynamicBodies: TCastleTransform;
  private
    RigidBodies: TCastleRigidBodyList;
    procedure AddForceAtPosition;
    procedure AddForce;
    procedure AddTorque;
    procedure ApplyImpulse;
    function ForceScale: Single;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  StateMain: TStateMain;

implementation

uses SysUtils, Math,
  CastleColors;

{ TStateMain ----------------------------------------------------------------- }

constructor TStateMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gamestatemain.castle-user-interface';
end;

procedure TStateMain.Start;
var
  T: TCastleTransform;
  RBody: TCastleRigidBody;
begin
  inherited;

  RigidBodies := TCastleRigidBodyList.Create;

  for T in DynamicBodies do
  begin
    RBody := T.FindBehavior(TCastleRigidBody) as TCastleRigidBody;
    if RBody <> nil then
      RigidBodies.Add(RBody);
  end;
end;

procedure TStateMain.Stop;
begin
  FreeAndNil(RigidBodies);
  inherited;
end;

procedure TStateMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);

  procedure ColorLabel(const Lab: TCastleLabel; const Active: Boolean);
  begin
    if Active then
      Lab.Color := Blue
    else
      Lab.Color := White;
  end;

const
  MoveSpeed = 10;
  ScaleIncrease = 2;
  RotationSpeed = 10;
begin
  inherited;
  { This virtual method is executed every frame.}
  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;

  { Transform SceneArrow by keys }

  if Container.Pressed[keyW] then
    SceneArrow.Translation := SceneArrow.Translation + Vector3(0, 0, -1) * SecondsPassed * MoveSpeed;
  if Container.Pressed[keyS] then
    SceneArrow.Translation := SceneArrow.Translation + Vector3(0, 0,  1) * SecondsPassed * MoveSpeed;
  if Container.Pressed[keyA] then
    SceneArrow.Translation := SceneArrow.Translation + Vector3(-1, 0, 0) * SecondsPassed * MoveSpeed;
  if Container.Pressed[keyD] then
    SceneArrow.Translation := SceneArrow.Translation + Vector3( 1, 0, 0) * SecondsPassed * MoveSpeed;

  if Container.Pressed[keyQ] then
    SceneArrow.Scale := SceneArrow.Scale * Vector3(1, 1, Power(ScaleIncrease, SecondsPassed));
  if Container.Pressed[keyE] then
    SceneArrow.Scale := SceneArrow.Scale * Vector3(1, 1, Power(1 / ScaleIncrease, SecondsPassed));

  if Container.Pressed[keyZ] then
    SceneArrow.Rotation := Vector4(0, 1, 0, SceneArrow.Rotation.W + SecondsPassed * RotationSpeed);
  if Container.Pressed[keyC] then
    SceneArrow.Rotation := Vector4(0, 1, 0, SceneArrow.Rotation.W - SecondsPassed * RotationSpeed);

  if Container.Pressed[key7] then
    AddForceAtPosition;
  if Container.Pressed[key8] then
    AddForce;
  if Container.Pressed[key9] then
    AddTorque;

  ColorLabel(LabelAddForceAtPosition, Container.Pressed[key7]);
  ColorLabel(LabelAddForce, Container.Pressed[key8]);
  ColorLabel(LabelAddTorque, Container.Pressed[key9]);
  ColorLabel(LabelApplyImpulse, Container.Pressed[key0]);
end;

function TStateMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if Event.IsKey(key0) then
  begin
    ApplyImpulse;
    Exit(true);
  end;
end;

function TStateMain.ForceScale: Single;
begin
  Result := SceneArrow.Scale.Z * 1;
end;

procedure TStateMain.AddForceAtPosition;
var
  RBody: TCastleRigidBody;
begin
  for RBody in RigidBodies do
    RBody.AddForceAtPosition(SceneArrow.Direction * ForceScale, SceneArrow.Translation);
end;

procedure TStateMain.AddForce;
var
  RBody: TCastleRigidBody;
begin
  for RBody in RigidBodies do
    RBody.AddForce(SceneArrow.Direction * ForceScale, false);
end;

procedure TStateMain.AddTorque;
var
  RBody: TCastleRigidBody;
begin
  for RBody in RigidBodies do
    RBody.AddTorque(SceneArrow.Direction * ForceScale);
end;

procedure TStateMain.ApplyImpulse;
var
  RBody: TCastleRigidBody;
begin
  for RBody in RigidBodies do
    RBody.ApplyImpulse(SceneArrow.Direction * ForceScale, SceneArrow.Translation);
end;

end.
