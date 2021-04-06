{ Main "playing game" state, where most of the game logic takes place.

  Feel free to use this code as a starting point for your own projects.
  (This code is in public domain, unlike most other CGE code which
  is covered by the LGPL license variant, see the COPYING.txt file.) }
unit GameStatePlay;

interface

uses Classes,
  CastleUIState, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleViewport, CastleScene, CastleVectors, CastleTransform,
  GameEnemy;

type
  TLevelBounds = class (TComponent)
  public
    Left: Single;
    Right: Single;
    Top: Single;
    Down: Single;
    constructor Create(AOwner: TComponent);override;
  end;

  TBullet = class(TCastleTransform)
  strict private
    Duration: Single;
  public
    constructor Create(AOwner: TComponent; BulletSpriteScene: TCastleScene); reintroduce;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

  { Main "playing game" state, where most of the game logic takes place. }
  TStatePlay = class(TUIState)
  strict private
    { Components designed using CGE editor, loaded from state_play.castle-user-interface. }
    LabelFps: TCastleLabel;
    MainViewport: TCastleViewport;
    ScenePlayer: TCastleScene;
    CheckboxCameraFollow: TCastleCheckbox;
    CheckboxAdvancedPlayer: TCastleCheckbox;

    { Checks this is firs Update when W key (jump) was pressed }
    WasJumpKeyPressed: Boolean;

    { Checks this is firs Update when Space key (shot) was pressed }
    WasShotKeyPressed: Boolean;

    { Player abilities }
    PlayerCanDoubleJump: Boolean;
    WasDoubleJump: Boolean;
    PlayerCanShot: Boolean;

    BulletSpriteScene: TCastleScene;

    { Level bounds }
    LevelBounds: TLevelBounds;

    { Enemies behaviours }
    Enemies: TEnemyList;

    procedure ConfigurePlatformPhysics(Platform: TCastleScene);
    procedure ConfigureCoinsPhysics(const Coin: TCastleScene);
    procedure ConfigurePowerUpsPhysics(const PowerUp: TCastleScene);
    procedure ConfigureGroundPhysics(const Ground: TCastleScene);
    procedure ConfigureStonePhysics(const Stone: TCastleScene);

    procedure ConfigurePlayerPhysics(const Player:TCastleScene);
    procedure ConfigurePlayerAbilities(const Player:TCastleScene);
    procedure PlayerCollisionEnter(const CollisionDetails: TPhysicsCollisionDetails);
    procedure ConfigureBulletSpriteScene;

    procedure ConfigureEnemyPhysics(const EnemyScene: TCastleScene);

    { Simplest version }
    procedure UpdatePlayerSimpleDependOnlyVelocity(const SecondsPassed: Single;
      var HandleInput: Boolean);

    { More advanced version with ray to check "Are we on ground?" }
    procedure UpdatePlayerByVelocityAndRay(const SecondsPassed: Single;
      var HandleInput: Boolean);

    { More advanced version with ray to check "Are we on ground?" and
      double jump }
    procedure UpdatePlayerByVelocityAndRayWithDblJump(const SecondsPassed: Single;
      var HandleInput: Boolean);

    procedure UpdatePlayerByVelocityAndPhysicsRayWithDblJump(const SecondsPassed: Single;
      var HandleInput: Boolean);

    procedure UpdatePlayerByVelocityAndPhysicsRayWithDblJumpShot(const SecondsPassed: Single;
      var HandleInput: Boolean);

    procedure Shot(BulletOwner: TComponent; const Origin, Direction: TVector3);

  public
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  StatePlay: TStatePlay;

implementation

uses
  SysUtils, Math,
  CastleLog,
  GameStateMenu;

{ TBullet }

constructor TBullet.Create(AOwner: TComponent; BulletSpriteScene: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TSphereCollider;
begin
  inherited Create(AOwner);

  Add(BulletSpriteScene);
  BulletSpriteScene.Visible := true;
  BulletSpriteScene.Translation := Vector3(0, 0, 0);

  RBody := TRigidBody.Create(Self);
  RBody.Setup2D;
  RBody.Dynamic := true;
  RBody.MaximalLinearVelocity := 0;

{  RBody.Animated := true;
  RBody.Setup2D;
  RBody.Gravity := true;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];
  RBody.MaximalLinearVelocity := 0;}


  Collider := TSphereCollider.Create(RBody);
  Collider.Radius :=  BulletSpriteScene.BoundingBox.Size.X / 2;
  //Collider.Mass := 10;

  RigidBody := RBody;
end;

procedure TBullet.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType
  );
begin
  inherited Update(SecondsPassed, RemoveMe);

  Duration := Duration + SecondsPassed;
  {if Duration > 5 then
    RemoveMe := rtRemoveAndFree;}
end;

{ TLevelBounds }

constructor TLevelBounds.Create(AOwner: TComponent);
begin
  Left := -3072;
  Right := 5120;
  Top := 3072;
  //Down := -1024;
  Down := -800;
end;

{ TStatePlay ----------------------------------------------------------------- }

procedure TStatePlay.ConfigurePlatformPhysics(Platform: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TBoxCollider;
  Size: TVector3;
begin
  RBody := TRigidBody.Create(Platform);
  RBody.Dynamic := false;
  RBody.Setup2D;
  RBody.Gravity := false;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];

  Collider := TBoxCollider.Create(RBody);

  Size.X := Platform.BoundingBox.SizeX;
  Size.Y := Platform.BoundingBox.SizeY;
  Size.Z := 1;

  Collider.Size := Size;

  Platform.RigidBody := RBody;
end;

procedure TStatePlay.ConfigureCoinsPhysics(const Coin: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TSphereCollider;
begin
  RBody := TRigidBody.Create(Coin);
  RBody.Dynamic := false;
  RBody.Setup2D;
  RBody.Gravity := false;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];
  RBody.MaximalLinearVelocity := 0;
  RBody.Trigger := true;

  Collider := TSphereCollider.Create(RBody);
  Collider.Radius := Coin.BoundingBox.SizeY / 8;
  Collider.Friction := 0.1;
  Collider.Restitution := 0.05;

  WritelnWarning('Coin collider: ' + FloatToStr(Collider.Radius));

  Coin.RigidBody := RBody;
end;

procedure TStatePlay.ConfigurePowerUpsPhysics(const PowerUp: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TSphereCollider;
begin
  RBody := TRigidBody.Create(PowerUp);
  RBody.Dynamic := false;
  //RBody.Animated := true;
  RBody.Setup2D;
  RBody.Gravity := false;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];
  RBody.MaximalLinearVelocity := 0;
  RBody.Trigger := true;

  Collider := TSphereCollider.Create(RBody);
  Collider.Radius := PowerUp.BoundingBox.SizeY / 8;
  Collider.Friction := 0.1;
  Collider.Restitution := 0.05;

  PowerUp.RigidBody := RBody;
end;

procedure TStatePlay.ConfigureGroundPhysics(const Ground: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TBoxCollider;
  Size: TVector3;
begin
  RBody := TRigidBody.Create(Ground);
  RBody.Dynamic := false;
  RBody.Setup2D;
  RBody.Gravity := false;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];

  Collider := TBoxCollider.Create(RBody);

  Size.X := Ground.BoundingBox.SizeX;
  Size.Y := Ground.BoundingBox.SizeY;
  Size.Z := 1;

  Collider.Size := Size;

  Ground.RigidBody := RBody;
end;

procedure TStatePlay.ConfigureStonePhysics(const Stone: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TBoxCollider;
  Size: TVector3;
begin
  RBody := TRigidBody.Create(Stone);
  RBody.Dynamic := false;
  RBody.Setup2D;
  RBody.Gravity := false;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];

  Collider := TBoxCollider.Create(RBody);

  Size.X := Stone.BoundingBox.SizeX;
  Size.Y := Stone.BoundingBox.SizeY;
  Size.Z := 1;

  Collider.Size := Size;

  Stone.RigidBody := RBody;
end;

procedure TStatePlay.ConfigurePlayerPhysics(const Player: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TCapsuleCollider;
  //ColliderBox: TBoxCollider;
begin
  RBody := TRigidBody.Create(Player);
  RBody.Dynamic := true;
  //RBody.Animated := true;
  RBody.Setup2D;
  RBody.Gravity := true;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];
  RBody.MaximalLinearVelocity := 0;
  RBody.OnCollisionEnter := @PlayerCollisionEnter;

  Collider := TCapsuleCollider.Create(RBody);
  Collider.Radius := ScenePlayer.BoundingBox.SizeX * 0.45; // little smaller than 50%
  Collider.Height := ScenePlayer.BoundingBox.SizeY - Collider.Radius * 2;
  Collider.Friction := 0.1;
  Collider.Restitution := 0.05;

  {ColliderSP := TSphereCollider.Create(RBody);
  ColliderSP.Radius := ScenePlayer.BoundingBox.SizeX * 0.45;}

  {ColliderBox := TBoxCollider.Create(RBody);
  ColliderBox.Size := Vector3(ScenePlayer.BoundingBox.SizeX, ScenePlayer.BoundingBox.SizeY, 60.0);
  ColliderBox.Friction := 0.1;
  ColliderBox.Restitution := 0.05;

  WritelnWarning('Player collider: ' + FloatToStr(ColliderBox.Size.X) + ', ' +
  FloatToStr(ColliderBox.Size.Y) + ', ' + FloatToStr(ColliderBox.Size.Z));}

  Player.RigidBody := RBody;

  WasJumpKeyPressed := false;
end;

procedure TStatePlay.ConfigurePlayerAbilities(const Player: TCastleScene);
begin
  PlayerCanDoubleJump := false;
  WasDoubleJump := false;
end;

procedure TStatePlay.PlayerCollisionEnter(
  const CollisionDetails: TPhysicsCollisionDetails);
begin
  if CollisionDetails.OtherTransform <> nil then
  begin
    if pos('GoldCoin', CollisionDetails.OtherTransform.Name) > 0 then
    begin
      WritelnWarning('Coin position ' + FloatToStr(CollisionDetails.OtherTransform.Translation.X) + ', ' +
      FloatToStr(CollisionDetails.OtherTransform.Translation.Y) + ', ' +
      FloatToStr(CollisionDetails.OtherTransform.Translation.Z));

      WritelnWarning('Player position ' + FloatToStr(ScenePlayer.Translation.X) + ', ' +
      FloatToStr(ScenePlayer.Translation.Y) + ', ' +
      FloatToStr(ScenePlayer.Translation.Z));

      CollisionDetails.OtherTransform.Exists := false;
    end else
    if pos('DblJump', CollisionDetails.OtherTransform.Name) > 0 then
    begin
      PlayerCanDoubleJump := true;
      CollisionDetails.OtherTransform.Exists := false;
    end;

  end;
end;

procedure TStatePlay.ConfigureEnemyPhysics(const EnemyScene: TCastleScene);
var
  RBody: TRigidBody;
  Collider: TSphereCollider;
begin
  RBody := TRigidBody.Create(EnemyScene);
  RBody.Dynamic := true;
  //RBody.Animated := true;
  RBody.Setup2D;
  RBody.Gravity := true;
  RBody.LinearVelocityDamp := 0;
  RBody.AngularVelocityDamp := 0;
  RBody.AngularVelocity := Vector3(0, 0, 0);
  RBody.LockRotation := [0, 1, 2];
  RBody.MaximalLinearVelocity := 0;
  RBody.OnCollisionEnter := @PlayerCollisionEnter;

  Collider := TSphereCollider.Create(RBody);
  Collider.Radius := EnemyScene.BoundingBox.SizeY * 0.45; // little smaller than 50%
  Collider.Friction := 0.1;
  Collider.Restitution := 0.05;

  {ColliderBox := TBoxCollider.Create(RBody);
  ColliderBox.Size := Vector3(ScenePlayer.BoundingBox.SizeX, ScenePlayer.BoundingBox.SizeY, 30.0);
  ColliderBox.Friction := 0.1;
  ColliderBox.Restitution := 0.05;}

  EnemyScene.RigidBody := RBody;
end;

procedure TStatePlay.ConfigureBulletSpriteScene;
begin
  BulletSpriteScene := TCastleScene.Create(FreeAtStop);
  BulletSpriteScene.URL := 'castle-data:/bullet/particle_darkGrey.png';
  BulletSpriteScene.Scale := Vector3(0.5, 0.5, 0.5);
end;

procedure TStatePlay.UpdatePlayerSimpleDependOnlyVelocity(
  const SecondsPassed: Single; var HandleInput: Boolean);
const
  JumpVelocity = 700;
  MaxHorizontalVelocity = 350;
var
  DeltaVelocity: TVector3;
  Vel: TVector3;
  PlayerOnGround: Boolean;
begin
  { This method is executed every frame.}

  DeltaVelocity := Vector3(0, 0, 0);
  Vel := ScenePlayer.RigidBody.LinearVelocity;

  { This is not ideal you can do another jump when Player is
    on top of the jump you can make next jump, but can be nice mechanic
    for someone }
  PlayerOnGround := (Abs(Vel.Y) < 10);

  if Container.Pressed.Items[keyW] then
  begin
    if (not WasJumpKeyPressed) and PlayerOnGround then
    begin
      DeltaVelocity.Y := JumpVelocity;
      WasJumpKeyPressed := true;
    end;
  end else
    WasJumpKeyPressed := false;


  if Container.Pressed.Items[keyD] and PlayerOnGround then
  begin
    DeltaVelocity.x := MaxHorizontalVelocity / 2;
  end;

  if Container.Pressed.Items[keyA] and PlayerOnGround then
  begin
    DeltaVelocity.x := - MaxHorizontalVelocity / 2;
  end;

  if Vel.X + DeltaVelocity.X > 0 then
    Vel.X := Min(Vel.X + DeltaVelocity.X, MaxHorizontalVelocity)
  else
    Vel.X := Max(Vel.X + DeltaVelocity.X, -MaxHorizontalVelocity);

  Vel.Y := Vel.Y + DeltaVelocity.Y;
  Vel.Z := 0;

  { Stop the player without slipping }
  if PlayerOnGround and (Container.Pressed.Items[keyD] = false) and (Container.Pressed.Items[keyA] = false) then
    Vel.X := 0;

  ScenePlayer.RigidBody.LinearVelocity := Vel;

  { Set animation }

  { We get here 20 because vertical velocity calculated by physics engine when
    player is on platform have no 0 but some small values to up and down sometimes
    It can fail when the player goes uphill (will set jump animation) or down
    will set fall animation }
  if Vel.Y > 20 then
    ScenePlayer.PlayAnimation('jump', true)
  else
  if Vel.Y < -20 then
    ScenePlayer.PlayAnimation('fall', true)
  else
    if Abs(Vel.X) > 1 then
    begin
      if ScenePlayer.CurrentAnimation.X3DName <> 'walk' then
        ScenePlayer.PlayAnimation('walk', true);
    end
    else
      ScenePlayer.PlayAnimation('idle', true);

  if Vel.X < 0 then
    ScenePlayer.Scale := Vector3(-1, 1, 1)
  else
    ScenePlayer.Scale := Vector3(1, 1, 1);
end;

procedure TStatePlay.UpdatePlayerByVelocityAndRay(const SecondsPassed: Single;
  var HandleInput: Boolean);
const
  JumpVelocity = 700;
  MaxHorizontalVelocity = 350;
var
  DeltaVelocity: TVector3;
  Vel: TVector3;
  PlayerOnGround: Boolean;
  Distance: Single;
begin
  { This method is executed every frame.}

  DeltaVelocity := Vector3(0, 0, 0);
  Vel := ScenePlayer.RigidBody.LinearVelocity;

  { Check player is on ground }
  if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(0, -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
    Distance) <> nil then
  begin
    // WritelnWarning('Distance ', FloatToStr(Distance));
    PlayerOnGround := Distance < 2;
  end else
    PlayerOnGround := false;


  { Two more checks Kraft - player should slide down when player just
    on the edge, maybe be can remove that when add Capsule collider }
  if PlayerOnGround = false then
  begin
    if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(-ScenePlayer.BoundingBox.SizeX * 0.40, -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
      Distance) <> nil then
    begin
      // WritelnWarning('Distance ', FloatToStr(Distance));
      PlayerOnGround := Distance < 2;
    end else
      PlayerOnGround := false;
  end;

  if PlayerOnGround = false then
  begin
    if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(ScenePlayer.BoundingBox.SizeX * 0.40, -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
      Distance) <> nil then
    begin
      // WritelnWarning('Distance ', FloatToStr(Distance));
      PlayerOnGround := Distance < 2;
    end else
      PlayerOnGround := false;
  end;

  if Container.Pressed.Items[keyW] then
  begin
    if (not WasJumpKeyPressed) and PlayerOnGround then
    begin
      DeltaVelocity.Y := JumpVelocity;
      WasJumpKeyPressed := true;
    end;
  end else
    WasJumpKeyPressed := false;


  if Container.Pressed.Items[keyD] and PlayerOnGround then
  begin
    DeltaVelocity.x := MaxHorizontalVelocity / 2;
  end;

  if Container.Pressed.Items[keyA] and PlayerOnGround then
  begin
    DeltaVelocity.x := - MaxHorizontalVelocity / 2;
  end;

  if Vel.X + DeltaVelocity.X > 0 then
    Vel.X := Min(Vel.X + DeltaVelocity.X, MaxHorizontalVelocity)
  else
    Vel.X := Max(Vel.X + DeltaVelocity.X, -MaxHorizontalVelocity);

  Vel.Y := Vel.Y + DeltaVelocity.Y;
  Vel.Z := 0;

  { Stop the player without slipping }
  if PlayerOnGround and (Container.Pressed.Items[keyD] = false) and (Container.Pressed.Items[keyA] = false) then
    Vel.X := 0;

  ScenePlayer.RigidBody.LinearVelocity := Vel;

  { Set animation }

  { We get here 20 because vertical velocity calculated by physics engine when
    player is on platform have no 0 but some small values to up and down sometimes
    It can fail when the player goes uphill (will set jump animation) or down
    will set fall animation }
  if Vel.Y > 20 then
    ScenePlayer.PlayAnimation('jump', true)
  else
  if Vel.Y < -20 then
    ScenePlayer.PlayAnimation('fall', true)
  else
    if Abs(Vel.X) > 1 then
    begin
      if ScenePlayer.CurrentAnimation.X3DName <> 'walk' then
        ScenePlayer.PlayAnimation('walk', true);
    end
    else
      ScenePlayer.PlayAnimation('idle', true);

  if Vel.X < 0 then
    ScenePlayer.Scale := Vector3(-1, 1, 1)
  else
    ScenePlayer.Scale := Vector3(1, 1, 1);
end;

procedure TStatePlay.UpdatePlayerByVelocityAndRayWithDblJump(
  const SecondsPassed: Single; var HandleInput: Boolean);
const
  JumpVelocity = 700;
  MaxHorizontalVelocity = 350;
var
  DeltaVelocity: TVector3;
  Vel: TVector3;
  PlayerOnGround: Boolean;
  Distance: Single;
  InSecondJump: Boolean;
begin
  { This method is executed every frame.}

  InSecondJump := false;

  DeltaVelocity := Vector3(0, 0, 0);
  Vel := ScenePlayer.RigidBody.LinearVelocity;

  { Check player is on ground }
  if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(0, -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
    Distance) <> nil then
  begin
    // WritelnWarning('Distance ', FloatToStr(Distance));
    PlayerOnGround := Distance < 2;
  end else
    PlayerOnGround := false;


  { Two more checks Kraft - player should slide down when player just
    on the edge, maye be can remove that when add Capsule collider }
  if PlayerOnGround = false then
  begin
    if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(-ScenePlayer.BoundingBox.SizeX * 0.40 , -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
      Distance) <> nil then
    begin
      // WritelnWarning('Distance ', FloatToStr(Distance));
      PlayerOnGround := Distance < 2;
    end else
      PlayerOnGround := false;
  end;

  if PlayerOnGround = false then
  begin
    if ScenePlayer.RayCast(ScenePlayer.Translation + Vector3(ScenePlayer.BoundingBox.SizeX * 0.40, -ScenePlayer.BoundingBox.SizeY / 2, 0), Vector3(0, -1, 0),
      Distance) <> nil then
    begin
      // WritelnWarning('Distance ', FloatToStr(Distance));
      PlayerOnGround := Distance < 2;
    end else
      PlayerOnGround := false;
  end;

  if PlayerOnGround then
    WasDoubleJump := false;

  if Container.Pressed.Items[keyW] then
  begin
    if (not WasJumpKeyPressed) and (PlayerOnGround or (PlayerCanDoubleJump and (not WasDoubleJump))) then
    begin
      if not PlayerOnGround then
      begin
        WasDoubleJump := true;
        InSecondJump := true;
        { In second jump just add diffrence betwen current Velocity and JumpVelocity }
        DeltaVelocity.Y := JumpVelocity - Vel.Y;
      end else
        DeltaVelocity.Y := JumpVelocity;
      WasJumpKeyPressed := true;
    end;
  end else
    WasJumpKeyPressed := false;

  if Container.Pressed.Items[keyD] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := MaxHorizontalVelocity / 2;
  end;

  if Container.Pressed.Items[keyA] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := - MaxHorizontalVelocity / 2;
  end;

  if Vel.X + DeltaVelocity.X > 0 then
    Vel.X := Min(Vel.X + DeltaVelocity.X, MaxHorizontalVelocity)
  else
    Vel.X := Max(Vel.X + DeltaVelocity.X, -MaxHorizontalVelocity);

  Vel.Y := Vel.Y + DeltaVelocity.Y;
  Vel.Z := 0;

  { Stop the player without slipping }
  if PlayerOnGround and (Container.Pressed.Items[keyD] = false) and (Container.Pressed.Items[keyA] = false) then
    Vel.X := 0;

  ScenePlayer.RigidBody.LinearVelocity := Vel;

  { Set animation }

  { We get here 20 because vertical velocity calculated by physics engine when
    player is on platform have no 0 but some small values to up and down sometimes
    It can fail when the player goes uphill (will set jump animation) or down
    will set fall animation }
  if (not PlayerOnGround) and (Vel.Y > 20) then
    ScenePlayer.PlayAnimation('jump', true)
  else
  if (not PlayerOnGround) and (Vel.Y < -20) then
    ScenePlayer.PlayAnimation('fall', true)
  else
    if Abs(Vel.X) > 1 then
    begin
      if ScenePlayer.CurrentAnimation.X3DName <> 'walk' then
        ScenePlayer.PlayAnimation('walk', true);
    end
    else
      ScenePlayer.PlayAnimation('idle', true);

  if Vel.X < 0 then
    ScenePlayer.Scale := Vector3(-1, 1, 1)
  else
    ScenePlayer.Scale := Vector3(1, 1, 1);
end;

procedure TStatePlay.UpdatePlayerByVelocityAndPhysicsRayWithDblJump(
  const SecondsPassed: Single; var HandleInput: Boolean);
const
  JumpVelocity = 700;
  MaxHorizontalVelocity = 350;
var
  DeltaVelocity: TVector3;
  Vel: TVector3;
  PlayerOnGround: Boolean;
  InSecondJump: Boolean;
begin
  { This method is executed every frame.}

  InSecondJump := false;

  DeltaVelocity := Vector3(0, 0, 0);
  Vel := ScenePlayer.RigidBody.LinearVelocity;

  { Check player is on ground }
  PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation,
    Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;

  { Two more checks Kraft - player should slide down when player just
    on the edge, but sometimes it stay and center ray dont "see" that we are
    on ground }
  if PlayerOnGround = false then
  begin
    PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation
      + Vector3(-ScenePlayer.BoundingBox.SizeX * 0.40, 0, 0),
      Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;
  end;

  if PlayerOnGround = false then
  begin
    PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation
      + Vector3(ScenePlayer.BoundingBox.SizeX * 0.40, 0, 0),
      Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;
  end;

  if PlayerOnGround then
    WasDoubleJump := false;

  if Container.Pressed.Items[keyW] then
  begin
    if (not WasJumpKeyPressed) and (PlayerOnGround or (PlayerCanDoubleJump and (not WasDoubleJump))) then
    begin
      if not PlayerOnGround then
      begin
        WasDoubleJump := true;
        InSecondJump := true;
        { In second jump just add diffrence betwen current Velocity and JumpVelocity }
        DeltaVelocity.Y := JumpVelocity - Vel.Y;
      end else
        DeltaVelocity.Y := JumpVelocity;
      WasJumpKeyPressed := true;
    end;
  end else
    WasJumpKeyPressed := false;

  if Container.Pressed.Items[keyD] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := MaxHorizontalVelocity / 2;
  end;

  if Container.Pressed.Items[keyA] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := - MaxHorizontalVelocity / 2;
  end;

  if Vel.X + DeltaVelocity.X > 0 then
    Vel.X := Min(Vel.X + DeltaVelocity.X, MaxHorizontalVelocity)
  else
    Vel.X := Max(Vel.X + DeltaVelocity.X, -MaxHorizontalVelocity);

  Vel.Y := Vel.Y + DeltaVelocity.Y;
  Vel.Z := 0;

  { Stop the player without slipping }
  if PlayerOnGround and (Container.Pressed.Items[keyD] = false) and (Container.Pressed.Items[keyA] = false) then
    Vel.X := 0;

  ScenePlayer.RigidBody.LinearVelocity := Vel;

  { Set animation }

  { We get here 20 because vertical velocity calculated by physics engine when
    player is on platform have no 0 but some small values to up and down sometimes
    It can fail when the player goes uphill (will set jump animation) or down
    will set fall animation }
  if (not PlayerOnGround) and (Vel.Y > 20) then
    ScenePlayer.PlayAnimation('jump', true)
  else
  if (not PlayerOnGround) and (Vel.Y < -20) then
    ScenePlayer.PlayAnimation('fall', true)
  else
    if Abs(Vel.X) > 1 then
    begin
      if ScenePlayer.CurrentAnimation.X3DName <> 'walk' then
        ScenePlayer.PlayAnimation('walk', true);
    end
    else
      ScenePlayer.PlayAnimation('idle', true);

  if Vel.X < 0 then
    ScenePlayer.Scale := Vector3(-1, 1, 1)
  else
    ScenePlayer.Scale := Vector3(1, 1, 1);
end;

procedure TStatePlay.UpdatePlayerByVelocityAndPhysicsRayWithDblJumpShot(
  const SecondsPassed: Single; var HandleInput: Boolean);
const
  JumpVelocity = 700;
  MaxHorizontalVelocity = 350;
var
  DeltaVelocity: TVector3;
  Vel: TVector3;
  PlayerOnGround: Boolean;
  InSecondJump: Boolean;
begin
  { This method is executed every frame.}

  InSecondJump := false;

  DeltaVelocity := Vector3(0, 0, 0);
  Vel := ScenePlayer.RigidBody.LinearVelocity;

  { Check player is on ground }
  PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation,
    Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;

  { Two more checks Kraft - player should slide down when player just
    on the edge, but sometimes it stay and center ray dont "see" that we are
    on ground }
  if PlayerOnGround = false then
  begin
    PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation
      + Vector3(-ScenePlayer.BoundingBox.SizeX * 0.40, 0, 0),
      Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;
  end;

  if PlayerOnGround = false then
  begin
    PlayerOnGround := ScenePlayer.RigidBody.PhysicsRayCast(ScenePlayer.Translation
      + Vector3(ScenePlayer.BoundingBox.SizeX * 0.40, 0, 0),
      Vector3(0, -1, 0), ScenePlayer.BoundingBox.SizeY / 2 + 5) <> nil;
  end;

  if PlayerOnGround then
    WasDoubleJump := false;

  if Container.Pressed.Items[keyW] then
  begin
    if (not WasJumpKeyPressed) and (PlayerOnGround or (PlayerCanDoubleJump and (not WasDoubleJump))) then
    begin
      if not PlayerOnGround then
      begin
        WasDoubleJump := true;
        InSecondJump := true;
        { In second jump just add diffrence betwen current Velocity and JumpVelocity }
        DeltaVelocity.Y := JumpVelocity - Vel.Y;
      end else
        DeltaVelocity.Y := JumpVelocity;
      WasJumpKeyPressed := true;
    end;
  end else
    WasJumpKeyPressed := false;

  if Container.Pressed.Items[keyD] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := MaxHorizontalVelocity / 2;
  end;

  if Container.Pressed.Items[keyA] and (PlayerOnGround or InSecondJump) then
  begin
    if InSecondJump then
      DeltaVelocity.x := MaxHorizontalVelocity / 3
    else
      DeltaVelocity.x := - MaxHorizontalVelocity / 2;
  end;

  if Vel.X + DeltaVelocity.X > 0 then
    Vel.X := Min(Vel.X + DeltaVelocity.X, MaxHorizontalVelocity)
  else
    Vel.X := Max(Vel.X + DeltaVelocity.X, -MaxHorizontalVelocity);

  Vel.Y := Vel.Y + DeltaVelocity.Y;
  Vel.Z := 0;

  { Stop the player without slipping }
  if PlayerOnGround and (Container.Pressed.Items[keyD] = false) and (Container.Pressed.Items[keyA] = false) then
    Vel.X := 0;

  ScenePlayer.RigidBody.LinearVelocity := Vel;

  { Set animation }

  { We get here 20 because vertical velocity calculated by physics engine when
    player is on platform have no 0 but some small values to up and down sometimes
    It can fail when the player goes uphill (will set jump animation) or down
    will set fall animation }
  if (not PlayerOnGround) and (Vel.Y > 20) then
    ScenePlayer.PlayAnimation('jump', true)
  else
  if (not PlayerOnGround) and (Vel.Y < -20) then
    ScenePlayer.PlayAnimation('fall', true)
  else
    if Abs(Vel.X) > 1 then
    begin
      if ScenePlayer.CurrentAnimation.X3DName <> 'walk' then
        ScenePlayer.PlayAnimation('walk', true);
    end
    else
      ScenePlayer.PlayAnimation('idle', true);

  if Vel.X < 0 then
    ScenePlayer.Scale := Vector3(-1, 1, 1)
  else
    ScenePlayer.Scale := Vector3(1, 1, 1);

  PlayerCanShot := true;
  if PlayerCanShot then
  begin
    if Container.Pressed.Items[keySpace] then
    begin
      if WasShotKeyPressed = false  then
      begin
        WasShotKeyPressed := true;

        Shot(ScenePlayer, ScenePlayer.LocalToWorld(Vector3(ScenePLayer.BoundingBox.SizeX / 2 + 5, 0, 0)),
          Vector3(ScenePlayer.Scale.X, 0, 0));
      end;
    end else
      WasShotKeyPressed := false;
  end;

end;

procedure TStatePlay.Shot(BulletOwner: TComponent; const Origin,
  Direction: TVector3);
var
  Bullet: TBullet;
begin
  Bullet := TBullet.Create(BulletOwner, BulletSpriteScene);
  Bullet.Translation := Origin;
  Bullet.RigidBody.LinearVelocity := Direction * Vector3(800, 800, 0);
  MainViewport.Items.Add(Bullet);
end;

procedure TStatePlay.Start;
var
  UiOwner: TComponent;

  PlatformsRoot: TCastleTransform;
  CoinsRoot: TCastleTransform;
  GroundsRoot: TCastleTransform;
  GroundsLineRoot: TCastleTransform;
  StonesRoot: TCastleTransform;
  EnemiesRoot: TCastleTransform;
  PowerUps: TCastleTransform;
  Enemy: TEnemy;
  EnemyScene: TCastleScene;
  I, J: Integer;
begin
  inherited;

  { Load designed user interface }
  InsertUserInterface('castle-data:/state_play.castle-user-interface', FreeAtStop, UiOwner);

  { Find components, by name, that we need to access from code }
  LabelFps := UiOwner.FindRequiredComponent('LabelFps') as TCastleLabel;
  MainViewport := UiOwner.FindRequiredComponent('MainViewport') as TCastleViewport;
  CheckboxCameraFollow := UiOwner.FindRequiredComponent('CheckboxCameraFollow') as TCastleCheckbox;
  CheckboxAdvancedPlayer := UiOwner.FindRequiredComponent('AdvancedPlayer') as TCastleCheckbox;

  ScenePlayer := UiOwner.FindRequiredComponent('ScenePlayer') as TCastleScene;


  WasShotKeyPressed := false;

  { Configure physics for platforms }
  PlatformsRoot := UiOwner.FindRequiredComponent('Platforms') as TCastleTransform;
  for I := 0 to PlatformsRoot.Count - 1 do
  begin
    WritelnWarning('Configure platform: ' + PlatformsRoot.Items[I].Name);
    ConfigurePlatformPhysics(PlatformsRoot.Items[I] as TCastleScene);
  end;

  { Configure physics for coins }
  CoinsRoot := UiOwner.FindRequiredComponent('Coins') as TCastleTransform;
  for I := 0 to CoinsRoot.Count - 1 do
  begin
    WritelnWarning('Configure coin: ' + CoinsRoot.Items[I].Name);
    ConfigureCoinsPhysics(CoinsRoot.Items[I] as TCastleScene);
  end;

  LevelBounds := TLevelBounds.Create(UiOwner);

  { Configure physics for ground  }

  GroundsRoot := UiOwner.FindRequiredComponent('Grounds') as TCastleTransform;
  for I := 0 to GroundsRoot.Count - 1 do
  begin
    if pos('GroundLine', GroundsRoot.Items[I].Name) = 1 then
    begin
      GroundsLineRoot := GroundsRoot.Items[I];
      for J := 0 to GroundsLineRoot.Count - 1 do
      begin
        ConfigureGroundPhysics(GroundsLineRoot.Items[J] as TCastleScene);
      end;
    end;
  end;

  StonesRoot := UiOwner.FindRequiredComponent('Stones') as TCastleTransform;
  for I := 0 to StonesRoot.Count - 1 do
  begin
    ConfigureStonePhysics(StonesRoot.Items[I] as TCastleScene);
  end;

  PowerUps := UiOwner.FindRequiredComponent('PowerUps') as TCastleTransform;
  for I := 0 to PowerUps.Count - 1 do
  begin
    ConfigurePowerUpsPhysics(PowerUps.Items[I] as TCastleScene);
  end;

  Enemies := TEnemyList.Create(true);
  EnemiesRoot := UiOwner.FindRequiredComponent('Enemies') as TCastleTransform;
  for I := 0 to EnemiesRoot.Count - 1 do
  begin
    EnemyScene := EnemiesRoot.Items[I] as TCastleScene;
    ConfigureEnemyPhysics(EnemyScene);
    { Below using nil as Owner of TEnemy, as the Enemies list already "owns"
      instances of this class, i.e. it will free them. }
    Enemy := TEnemy.Create(nil);
    EnemyScene.AddBehavior(Enemy);
    Enemies.Add(Enemy);
  end;

  { Configure physics for player }
  ConfigurePlayerPhysics(ScenePlayer);
  ConfigurePlayerAbilities(ScenePlayer);


  ConfigureBulletSpriteScene;
end;

procedure TStatePlay.Stop;
begin
  FreeAndNil(Enemies);
  inherited;
end;

procedure TStatePlay.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  CamPos: TVector3;
  ViewHeight: Single;
  ViewWidth: Single;
begin
  inherited;
  { This virtual method is executed every frame.}

  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;

  if CheckboxCameraFollow.Checked then
  begin
    ViewHeight := MainViewport.Camera.Orthographic.EffectiveHeight;
    ViewWidth := MainViewport.Camera.Orthographic.EffectiveWidth;

    CamPos := MainViewport.Camera.Position;
    CamPos.X := ScenePlayer.Translation.X;
    CamPos.Y := ScenePlayer.Translation.Y;

    { Camera always stay on level }
    if CamPos.Y - ViewHeight / 2 < LevelBounds.Down then
       CamPos.Y := LevelBounds.Down + ViewHeight / 2;

    if CamPos.Y + ViewHeight / 2 > LevelBounds.Top then
       CamPos.Y := LevelBounds.Top - ViewHeight / 2;

    if CamPos.X - ViewWidth / 2 < LevelBounds.Left then
       CamPos.X := LevelBounds.Left + ViewWidth / 2;

    if CamPos.X + ViewWidth / 2 > LevelBounds.Right then
       CamPos.X := LevelBounds.Right - ViewWidth / 2;

    MainViewport.Camera.Position := CamPos;
  end;

  if CheckboxAdvancedPlayer.Checked then
    { uncomment to see less advanced versions }
    //UpdatePlayerByVelocityAndRay(SecondsPassed, HandleInput)
    //UpdatePlayerByVelocityAndRayWithDblJump(SecondsPassed, HandleInput)
    //UpdatePlayerByVelocityAndPhysicsRayWithDblJump(SecondsPassed, HandleInput)
    UpdatePlayerByVelocityAndPhysicsRayWithDblJumpShot(SecondsPassed, HandleInput)
  else
    UpdatePlayerSimpleDependOnlyVelocity(SecondsPassed, HandleInput);
end;

function TStatePlay.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  { This virtual method is executed when user presses
    a key, a mouse button, or touches a touch-screen.

    Note that each UI control has also events like OnPress and OnClick.
    These events can be used to handle the "press", if it should do something
    specific when used in that UI control.
    The TStatePlay.Press method should be used to handle keys
    not handled in children controls.
  }

  if Event.IsKey(keyF5) then
  begin
    Container.SaveScreenToDefaultFile;
    Exit(true);
  end;

  if Event.IsKey(keyEscape) then
  begin
    TUIState.Current := StateMenu;
    Exit(true);
  end;
end;

end.
