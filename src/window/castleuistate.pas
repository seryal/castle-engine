{
  Copyright 2015-2015 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ UI state (TUIState). }
unit CastleUIState;

interface

uses Classes, FGL,
  CastleConfig, CastleKeysMouse, CastleImages, CastleUIControls,
  CastleGLImages, CastleVectors;

type
  { UI state, a useful singleton to manage the state of your game UI.

    Only one state is @italic(current) at a given time, it can
    be get or set using the TUIState.Current property.

    Each state has comfortable @link(Start) and @link(Finish)
    methods that you can override to perform work when state becomes
    current, or stops being current. Most importantly, you can
    add/remove additional state-specific UI controls in @link(Start) and @link(Finish)
    methods. Add them in @link(Start) method like
    @code(StateContainer.Controls.InsertFront(...)), remove them by
    @code(StateContainer.Controls.Remove(...)).

    Current state is also placed on the list of container controls.
    (Always @italic(under) state-specific UI controls you added
    to container in @link(Start) method.) This way state is notified
    about UI events, and can react to them. In case of events that
    can be "handled" (like TUIControl.Press, TUIControl.Release events)
    the state is notified about them only if no other state-specific
    UI control handled them.

    This way state can

    @unorderedList(
      @item(catch press/release and similar events, when no other
        state-specific control handled them,)
      @item(catch update, GL context open/close and other useful events,)
      @item(can have it's own render function, to directly draw UI.)
    )

    See the TUIControl class for a lot of useful methods that you can
    override in your state descendants to capture various events. }
  TUIState = class(TUIControl)
  private
  type
    TDataImage = class
      Image: TCastleImage;
      GLImage: TGLImage;
      destructor Destroy; override;
    end;
    TDataImageList = specialize TFPGObjectList<TDataImage>;
  var
    FDataImages: TDataImageList;
    FStartContainer: TUIContainer;
    class var FCurrent: TUIState;
    class function GetCurrent: TUIState; static;
    class procedure SetCurrent(const Value: TUIState); static;
  protected
    { Adds image to the list of automatically loaded images for this state.
      Path is automatically wrapped in ApplicationData(Path) to get URL.
      The basic image (TCastleImage) is loaded immediately,
      and always available, under DataImage(Index).
      The OpenGL image resource (TGLImage) is loaded when GL context
      is active, available under DataGLImage(Index).
      Where Index is the return value of this method. }
    function AddDataImage(const Path: string): Integer;
    function DataImage(const Index: Integer): TCastleImage;
    function DataGLImage(const Index: Integer): TGLImage;
    { Container on which state works. By default, this is Application.MainWindow.
      When the state is current, then @link(Container) property (from
      ancestor, see TUIControl.Container) is equal to this. }
    function StateContainer: TUIContainer; virtual;
  public
    class property Current: TUIState read GetCurrent write SetCurrent;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { State becomes current.
      This is called right before adding the state to the
      @code(StateContainer.Controls) list, so the state methods
      GLContextOpen and ContainerResize will be called next (as for all
      normal TUIControl). }
    procedure Start; virtual;

    { State is no longer current.
      This is called after removing the state from the
      @code(StateContainer.Controls) list.

      This is always called to finalize the started state.
      When the current state is destroyed, it's @link(Finish) is called
      too. So you can use this method to reliably finalize whatever
      you initialized in @link(Start). }
    procedure Finish; virtual;

    function PositionInside(const Position: TVector2Single): boolean; override;
    procedure GLContextOpen; override;
    procedure GLContextClose; override;
  end;

implementation

uses SysUtils,
  CastleWindow, CastleWarnings, CastleFilesUtils;

{ TUIState.TDataImage ---------------------------------------------------------- }

destructor TUIState.TDataImage.Destroy;
begin
  FreeAndNil(Image);
  FreeAndNil(GLImage);
  inherited;
end;

{ TUIState --------------------------------------------------------------------- }

class function TUIState.GetCurrent: TUIState;
begin
  Result := FCurrent;
end;

class procedure TUIState.SetCurrent(const Value: TUIState);
var
  ControlsCount, PositionInControls: Integer;
  NewControls: TUIControlList;
begin
  if FCurrent <> Value then
  begin
    if FCurrent <> nil then
    begin
      FCurrent.StateContainer.Controls.Remove(FCurrent);
      FCurrent.Finish;
    end;
    FCurrent := Value;
    if FCurrent <> nil then
    begin
      NewControls := FCurrent.StateContainer.Controls;
      ControlsCount := NewControls.Count;
      FCurrent.Start;
      { actually insert FCurrent, this will also call GLContextOpen
        and ContainerResize.
        However, check first that we're still within the same state,
        to safeguard from the fact that FCurrent.Start changed state
        (like the loading state, that changes to play state immediately in start). }
      if FCurrent = Value then
      begin
        PositionInControls := NewControls.Count - ControlsCount;
        if PositionInControls < 0 then
        begin
          OnWarning(wtMinor, 'State', 'TUIState.Start removed some controls from container');
          PositionInControls := 0;
        end;
        NewControls.Insert(PositionInControls, FCurrent);
      end;
    end;
  end;
end;

function TUIState.StateContainer: TUIContainer;
begin
  if FStartContainer <> nil then
    { between Start and Finish, be sure to return the same thing
      from StateContainer method. Also makes it working when Application
      is nil when destroying state from CastleWindow finalization. }
    Result := FStartContainer else
    Result := Application.MainWindow.Container;
end;

constructor TUIState.Create(AOwner: TComponent);
begin
  inherited;
  FDataImages := TDataImageList.Create;
end;

destructor TUIState.Destroy;
begin
  { finish yourself, if current }
  if Current = Self then
    Current := nil;
  FreeAndNil(FDataImages);
  inherited;
end;

procedure TUIState.Start;
begin
  FStartContainer := StateContainer;
end;

procedure TUIState.Finish;
begin
  FStartContainer := nil;
end;

function TUIState.AddDataImage(const Path: string): Integer;
var
  DI: TDataImage;
begin
  DI := TDataImage.Create;
  DI.Image := LoadImage(ApplicationData(Path), []);
  if GLInitialized then
    DI.GLImage := TGLImage.Create(DI.Image, true);
  Result := FDataImages.Add(DI);
end;

function TUIState.DataImage(const Index: Integer): TCastleImage;
begin
  Result := FDataImages[Index].Image;
end;

function TUIState.DataGLImage(const Index: Integer): TGLImage;
begin
  Result := FDataImages[Index].GLImage;
end;

function TUIState.PositionInside(const Position: TVector2Single): boolean;
begin
  Result := true;
end;

procedure TUIState.GLContextOpen;
var
  I: Integer;
  DI: TDataImage;
begin
  inherited;
  for I := 0 to FDataImages.Count - 1 do
  begin
    DI := FDataImages[I];
    if DI.GLImage = nil then
      DI.GLImage := TGLImage.Create(DI.Image, true);
  end;
end;

procedure TUIState.GLContextClose;
var
  I: Integer;
begin
  if FDataImages <> nil then
    for I := 0 to FDataImages.Count - 1 do
      FreeAndNil(FDataImages[I].GLImage);
  inherited;
end;

end.
