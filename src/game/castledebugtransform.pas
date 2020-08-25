{
  Copyright 2006-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Helpers to visualize debug information about transformation. }
unit CastleDebugTransform;

interface

uses Classes,
  CastleTransform, CastleBoxes, X3DNodes, CastleScene, CastleVectors, CastleColors;

type
  { 3D axis, as an X3D node, to easily visualize debug things.
    This is useful in connection with your custom TDebugTransform descendants,
    to show an axis to visualize something.

    Create it and add the @link(Root) to your X3D scene graph
    within some @link(TCastleSceneCore.RootNode).
    You can change properties like @link(Position) at any time
    (before and after adding the @link(TCastleSceneCore.RootNode)
    to some graph). }
  TDebugAxis = class(TComponent)
  strict private
    FShape: TShapeNode;
    FGeometry: TLineSetNode;
    FCoord: TCoordinateNode;
    FTransform: TTransformNode;
    function GetRender: boolean;
    procedure SetRender(const Value: boolean);
    procedure SetPosition(const Value: TVector3);
    procedure SetScaleFromBox(const Value: TBox3D);
  public
    constructor Create(const AOwner: TComponent; const Color: TCastleColorRGB); reintroduce;
    property Root: TTransformNode read FTransform;
    property Render: boolean read GetRender write SetRender;
    property Position: TVector3 {read GetPosition} {} write SetPosition;
    property ScaleFromBox: TBox3D {read GetScale} {} write SetScaleFromBox;
  end;

  { 3D box, as an X3D node, to easily visualize debug things.
    This is a ready construction using X3D TBoxNode, TShapeNode, TTransformNode
    to give you a comfortable box visualization.

    This is useful in connection with your custom TDebugTransform descendants,
    to show an axis to visualize something.

    Create it and add the @link(Root) to your X3D scene graph
    within some @link(TCastleSceneCore.RootNode).
    You can change properties like @link(Box) at any time
    (before and after adding the @link(TCastleSceneCore.RootNode)
    to some graph). }
  TDebugBox = class(TComponent)
  strict private
    FColor: TCastleColor;
    FTransform: TTransformNode;
    FShape: TShapeNode;
    FGeometry: TBoxNode;
    FMaterial: TUnlitMaterialNode;
    procedure SetBox(const Value: TBox3D);
    procedure SetColor(const AValue: TCastleColor);
  public
    constructor Create(AOwner: TComponent); override;
    constructor Create(const AOwner: TComponent; const AColor: TCastleColorRGB); reintroduce;
      deprecated 'use Create(AOwner) and adjust Color property';
    property Root: TTransformNode read FTransform;
    property Box: TBox3D {read GetBox} {} write SetBox;
    property Color: TCastleColor read FColor write SetColor;
  end;

  { 3D sphere, as an X3D node, to easily visualize debug things.
    This is a ready construction using X3D TSphereNode, TShapeNode, TTransformNode
    to give you a comfortable sphere visualization.

    This is useful in connection with your custom TDebugTransform descendants,
    to show an axis to visualize something.

    Create it and add the @link(Root) to your X3D scene graph
    within some @link(TCastleSceneCore.RootNode).
    You can change properties like @link(Position) at any time
    (before and after adding the @link(TCastleSceneCore.RootNode)
    to some graph). }
  TDebugSphere = class(TComponent)
  strict private
    FTransform: TTransformNode;
    FShape: TShapeNode;
    FGeometry: TSphereNode;
    function GetRender: boolean;
    procedure SetRender(const Value: boolean);
    procedure SetPosition(const Value: TVector3);
    procedure SetRadius(const Value: Single);
  public
    constructor Create(const AOwner: TComponent; const Color: TCastleColorRGB); reintroduce;
    property Root: TTransformNode read FTransform;
    property Render: boolean read GetRender write SetRender;
    property Position: TVector3 {read GetPosition} {} write SetPosition;
    property Radius: Single {read GetRadius} {} write SetRadius;
  end;

  { 3D arrow, as an X3D node, to easily visualize debug things.

    This is useful in connection with your custom TDebugTransform descendants,
    to show an arrow to visualize something.

    Create it and add the @link(Root) to your X3D scene graph
    within some @link(TCastleSceneCore.RootNode). }
  TDebugArrow = class(TComponent)
  strict private
    FTransform: TTransformNode;
    FShape: TShapeNode;
    FOrigin, FDirection: TVector3;
    Coord: TCoordinateNode;
    procedure SetOrigin(const Value: TVector3);
    procedure SetDirection(const Value: TVector3);
    procedure UpdateGeometry;
  public
    constructor Create(const AOwner: TComponent; const Color: TCastleColorRGB); reintroduce;
    property Root: TTransformNode read FTransform;
    property Origin: TVector3 read FOrigin write SetOrigin;
    property Direction: TVector3 read FDirection write SetDirection;
  end;

  { Visualization of a bounding volume of a TCastleTransform instance.
    After constructing this, call @link(Attach) to attach this to some
    @link(TCastleTransform) instance.

    Then set @link(Exists) to control whether the debug visualization
    should actually be shown. We take care to only actually construct
    internal TCastleScene when the @link(Exists) becomes @true,
    so you can construct TDebugTransform instance always, even in release mode --
    it does not take up resources if never visible. }
  TDebugTransformBox = class(TComponent)
  strict private
    type
      TInternalScene = class(TCastleScene)
        Container: TDebugTransformBox;
        procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
      end;
    var
      FBox: TDebugBox;
      FTransform: TMatrixTransformNode;
      FWorldSpace: TAbstractX3DGroupingNode;
      FParent: TCastleTransform;
      FScene: TInternalScene;
      FExists: boolean;
      FBoxColor: TCastleColor;
    procedure SetBoxColor(const AValue: TCastleColor);
    procedure UpdateSafe;
    procedure SetExists(const Value: boolean);
    procedure Initialize;
  strict protected
    { Called when internal scene is constructed.
      You can override it in desdendants to e.g. add more stuff to WorldSpace. }
    procedure InitializeNodes; virtual;

    { Called continuosly when internal scene should be updated.
      You can override it in desdendants to e.g. update the things you added
      in @link(Initialize). }
    procedure Update; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Attach(const AParent: TCastleTransform);
    property Parent: TCastleTransform read FParent;
    { Is the debug visualization visible. }
    property Exists: boolean read FExists write SetExists default false;
    { Add additional things that are expressed in world-space under this transform.
      Be sure to call @link(ChangedScene) afterwards. }
    property WorldSpace: TAbstractX3DGroupingNode read FWorldSpace;
    property BoxColor: TCastleColor read FBoxColor write SetBoxColor;
    procedure ChangedScene;
  end;

  { Like TDebugTransformBox, but visualizes also additional properties.

    Adds visualization of:
    - TCastleTransform.Middle
    - TCastleTransform.Sphere
    - TCastleTransform.Direction }
  TDebugTransform = class(TDebugTransformBox)
  strict private
    FDirectionArrow: TDebugArrow;
    FSphere: TDebugSphere;
    FMiddleAxis: TDebugAxis;
  strict protected
    procedure InitializeNodes; override;
    procedure Update; override;
  end;

implementation

uses CastleLog;

{ TDebugAxis ----------------------------------------------------------------- }

constructor TDebugAxis.Create(const AOwner: TComponent; const Color: TCastleColorRGB);
var
  Material: TUnlitMaterialNode;
begin
  inherited Create(AOwner);

  FCoord := TCoordinateNode.Create;
  FCoord.SetPoint([
    Vector3(-1,  0,  0), Vector3(1, 0, 0),
    Vector3( 0, -1,  0), Vector3(0, 1, 0),
    Vector3( 0,  0, -1), Vector3(0, 0, 1)
  ]);

  FGeometry := TLineSetNode.Create;
  FGeometry.SetVertexCount([2, 2, 2]);
  FGeometry.Coord := FCoord;

  Material := TUnlitMaterialNode.Create;
  Material.EmissiveColor := Color;

  FShape := TShapeNode.Create;
  FShape.Geometry := FGeometry;
  FShape.Material := Material;

  FTransform := TTransformNode.Create;
  FTransform.AddChildren(FShape);
end;

function TDebugAxis.GetRender: boolean;
begin
  Result := FShape.Render;
end;

procedure TDebugAxis.SetRender(const Value: boolean);
begin
  FShape.Render := Value;
end;

procedure TDebugAxis.SetPosition(const Value: TVector3);
begin
  FTransform.Translation := Value;
end;

procedure TDebugAxis.SetScaleFromBox(const Value: TBox3D);
var
  ScaleFactor: Single;
begin
  ScaleFactor := Value.AverageSize(true, 1) / 2;
  FTransform.Scale := Vector3(ScaleFactor, ScaleFactor, ScaleFactor);
end;

{ TDebugBox ----------------------------------------------------------------- }

constructor TDebugBox.Create(const AOwner: TComponent; const AColor: TCastleColorRGB);
begin
  Create(AOwner);
  Color := Vector4(AColor, 1);
end;

constructor TDebugBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FColor := White;

  FGeometry := TBoxNode.Create;

  FShape := TShapeNode.Create;
  FShape.Geometry := FGeometry;
  FShape.Shading := shWireframe;

  FMaterial := TUnlitMaterialNode.Create;
  FMaterial.EmissiveColor := FColor.XYZ;
  FMaterial.Transparency := 1 - FColor.W;
  FShape.Material := FMaterial;

  FTransform := TTransformNode.Create;
  FTransform.AddChildren(FShape);
end;

procedure TDebugBox.SetBox(const Value: TBox3D);
begin
  FShape.Render := not Value.IsEmpty;
  if FShape.Render then
  begin
    FGeometry.Size := Value.Size;
    FTransform.Translation := Value.Center;
  end;
end;

procedure TDebugBox.SetColor(const AValue: TCastleColor);
begin
  if TCastleColor.PerfectlyEquals(FColor, AValue) then Exit;
  FColor := AValue;
  FMaterial.EmissiveColor := FColor.XYZ;
  FMaterial.Transparency := 1 - FColor.W;
end;

{ TDebugSphere ----------------------------------------------------------------- }

constructor TDebugSphere.Create(const AOwner: TComponent; const Color: TCastleColorRGB);
var
  Material: TUnlitMaterialNode;
begin
  inherited Create(AOwner);

  FGeometry := TSphereNode.Create;
  FGeometry.Slices := 10;
  FGeometry.Stacks := 10;

  FShape := TShapeNode.Create;
  FShape.Geometry := FGeometry;
  FShape.Shading := shWireframe;

  Material := TUnlitMaterialNode.Create;
  Material.EmissiveColor := Color;
  FShape.Material := Material;

  FTransform := TTransformNode.Create;
  FTransform.AddChildren(FShape);
end;

function TDebugSphere.GetRender: boolean;
begin
  Result := FShape.Render;
end;

procedure TDebugSphere.SetRender(const Value: boolean);
begin
  FShape.Render := Value;
end;

procedure TDebugSphere.SetPosition(const Value: TVector3);
begin
  FTransform.Translation := Value;
end;

procedure TDebugSphere.SetRadius(const Value: Single);
begin
  FGeometry.Radius := Value;
end;

{ TDebugArrow ----------------------------------------------------------------- }

constructor TDebugArrow.Create(const AOwner: TComponent; const Color: TCastleColorRGB);
var
  Material: TUnlitMaterialNode;
  FGeometry: TLineSetNode;
begin
  inherited Create(AOwner);

  FGeometry := TLineSetNode.CreateWithTransform(FShape, FTransform);

  Material := TUnlitMaterialNode.Create;
  Material.EmissiveColor := Color;
  FShape.Material := Material;

  Coord := TCoordinateNode.Create;

  FGeometry.Coord := Coord;
  FGeometry.SetVertexCount([2, 2, 2, 2, 2]);

  { Make the initial geometry. Although it is useless, this will avoid warning
    "Too much lines (not enough coordinates) in LineSet". }
  UpdateGeometry;
end;

procedure TDebugArrow.SetOrigin(const Value: TVector3);
begin
  if not TVector3.PerfectlyEquals(FOrigin, Value) then
  begin
    FOrigin := Value;
    UpdateGeometry;
  end;
end;

procedure TDebugArrow.SetDirection(const Value: TVector3);
begin
  if not TVector3.PerfectlyEquals(FDirection, Value) then
  begin
    FDirection := Value;
    UpdateGeometry;
  end;
end;

procedure TDebugArrow.UpdateGeometry;
var
  OrthoDirection, OrthoDirection2: TVector3;
begin
  OrthoDirection := AnyOrthogonalVector(Direction);
  OrthoDirection2 := TVector3.CrossProduct(Direction, OrthoDirection);

  OrthoDirection := OrthoDirection.AdjustToLength(Direction.Length / 4);
  OrthoDirection2 := OrthoDirection2.AdjustToLength(Direction.Length / 4);

  Coord.SetPoint([
    Origin,
    Origin + Direction,
    Origin + Direction,
    Origin + Direction * 0.75 + OrthoDirection,
    Origin + Direction,
    Origin + Direction * 0.75 - OrthoDirection,
    Origin + Direction,
    Origin + Direction * 0.75 + OrthoDirection2,
    Origin + Direction,
    Origin + Direction * 0.75 - OrthoDirection2
  ]);
end;

{ TDebugTransform.TInternalScene ---------------------------------------------------- }

procedure TDebugTransformBox.TInternalScene.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  Container.UpdateSafe;
end;

{ TDebugTransformBox ---------------------------------------------------- }

constructor TDebugTransformBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBoxColor := Gray;
end;

procedure TDebugTransformBox.Initialize;
var
  Root: TX3DRootNode;
begin
  FTransform := TMatrixTransformNode.Create;
  FWorldSpace := FTransform;

  FBox := TDebugBox.Create(Self);
  FBox.Color := FBoxColor;
  WorldSpace.AddChildren(FBox.Root);

  InitializeNodes;

  Root := TX3DRootNode.Create;
  Root.AddChildren(FTransform);

  FScene := TInternalScene.Create(Self);
  FScene.Container := Self;
  FScene.Load(Root, true);
  FScene.Collides := false;
  FScene.Pickable := false;
  FScene.CastShadowVolumes := false;
  FScene.ExcludeFromStatistics := true;
  FScene.InternalExcludeFromParentBoundingVolume := true;
  FScene.Exists := FExists;
  FScene.SetTransient;
end;

procedure TDebugTransformBox.InitializeNodes;
begin
end;

procedure TDebugTransformBox.Attach(const AParent: TCastleTransform);
begin
  if FScene = nil then
    Initialize
  else
  begin
    // remove self from previous parent
    if FParent <> nil then
      FParent.Remove(FScene);
  end;

  FParent := AParent;
  FParent.Add(FScene);
  UpdateSafe;
end;

procedure TDebugTransformBox.SetExists(const Value: boolean);
begin
  if FExists <> Value then
  begin
    FExists := Value;
    if FScene <> nil then
      FScene.Exists := Value;
    if Value then
      UpdateSafe;
  end;
end;

procedure TDebugTransformBox.UpdateSafe;
begin
  if Exists and
     (FParent <> nil) and
     { resign when FParent.World unset,
       as then FParent.Middle and FParent.PreferredHeight cannot be calculated }
     (FParent.World <> nil) then
  begin
    if FScene = nil then
      Initialize;
    Update;
  end;
end;

procedure TDebugTransformBox.SetBoxColor(const AValue: TCastleColor);
begin
  FBoxColor := AValue;
  if FBox <> nil then
    FBox.Color := AValue;
end;

procedure TDebugTransformBox.Update;
begin
  // update FTransform to cancel parent's transformation
  FTransform.Matrix := FParent.InverseTransform;

  // show FParent.BoundingBox
  FBox.Box := FParent.BoundingBox;
end;

procedure TDebugTransformBox.ChangedScene;
begin
  FScene.ChangedAll;
end;

{ TDebugTransform ---------------------------------------------------- }

procedure TDebugTransform.InitializeNodes;
begin
  inherited;

  FDirectionArrow := TDebugArrow.Create(Self, BlueRGB);
  WorldSpace.AddChildren(FDirectionArrow.Root);

  FSphere := TDebugSphere.Create(Self, GrayRGB);
  WorldSpace.AddChildren(FSphere.Root);

  FMiddleAxis := TDebugAxis.Create(Self, YellowRGB);
  WorldSpace.AddChildren(FMiddleAxis.Root);
end;

procedure TDebugTransform.Update;
var
  R: Single;
begin
  inherited;

  // show FParent.Sphere
  FSphere.Render := Parent.Sphere(R);
  if FSphere.Render then
  begin
    FSphere.Position := Parent.Middle;
    FSphere.Radius := R;
  end;

  // show FParent.Direction
  FDirectionArrow.Origin := Parent.Middle;
  FDirectionArrow.Direction := Parent.Direction;

  // show FParent.Middle
  FMiddleAxis.Position := Parent.Middle;
  FMiddleAxis.ScaleFromBox := Parent.BoundingBox;
end;

end.
