{
  Copyright 2013-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Initializes OpenGL context using Windows WGL. }
unit CastleGLContextWGL;

interface

uses Windows, SysUtils,
  CastleVectors;

type
  EGLContextNotPossible = class(Exception);

  { Required OpenGL context capabilities.
    See corresponding TCastleWindow properties for docs. }
  TGLContextRequirements = class
    DoubleBuffer: Boolean;
    ColorBits: Cardinal;
    RedBits, GreenBits, BlueBits: Cardinal;
    DepthBits: Cardinal;
    AlphaBits: Cardinal;
    StencilBits: Cardinal;
    MultiSampling: Cardinal;
    AccumBits: TVector4Cardinal;

    { Check do given OpenGL buffers configuration satisfies the
      requested configuration.

      So it checks does

      @preformatted(
        ProvidedStencilBits >= StencilBits and
        ProvidedDepthBits >= DepthBits ...
      )

      and so on. If not, EGLContextNotPossible is raised with detailed
      description (which buffer constraint is not satisfied -- e.g. maybe
      the stencil buffer is not available).

      Note that ProvidedMultiSampling is not checked if MultiSampling is <= 1.
      In other words, if multisampling was not required, ProvidedMultiSampling
      doesn't matter --- it's Ok even ProvidedMultiSampling = 0 and
      MultiSampling = 1, which happens commonly (since our MultiSampling = 1 means
      "no multisampling" and is default, but most backends returns num_samples
      (or something equivalent) as = 0 when multisampling not supported). }
    procedure CheckRequestedBufferAttributes(const ProviderName: string;
      ProvidedStencilBits, ProvidedDepthBits, ProvidedAlphaBits,
      ProvidedAccumRedBits, ProvidedAccumGreenBits, ProvidedAccumBlueBits,
      ProvidedAccumAlphaBits, ProvidedMultiSampling: Cardinal);

    { Current OpenGL buffers configuration required.
      Stuff like DoubleBuffer, AlphaBits, DepthBits,
      StencilBits, AccumBits etc.
      This simply returns a text description of these properties.

      It does not describe the current OpenGL context parameters.
      (It doesn't even need an OpenGL context open.)

      Useful for constructing messages e.g. for EGLContextNotPossible exceptions. }
    function RequestedBufferAttributes: String;
  end;

  TGLContextWGL = class
  public
    // Set this before using ContextCreate and other methods
    WndPtr: HWND;
    h_Dc: HDC;
    WindowCaption: String;
    WndClassName: UnicodeString;
    SharedContext: TGLContextWGL; //< leave nil to not share

    // Created by ContextCreate, destroyed by ContextDestroy
    h_GLRc: HGLRC;

    { Methods compatible with castlewindow_egl.inc.
      @groupBegin }
    procedure ContextCreate(const Requirements: TGLContextRequirements);
    procedure ContextDestroy;
    { @groupEnd }

    procedure MakeCurrent;
    procedure SwapBuffers;
  end;

implementation

{ TODO: Use this approach to initialize OpenGL contexts everywhere.
  Use it in castlewindow_wgl.inc .
  Move TGLContextRequirements to some cross-platform unit,
  make TGLContext cross-platform and abstract. }

uses {$ifdef FPC} CastleGL, {$else} OpenGL, OpenGLext, {$endif}
  CastleUtils, CastleStringUtils, CastleGLUtils, CastleLog;

procedure TGLContextWGL.ContextCreate(const Requirements: TGLContextRequirements);

  { Both SetPixelFormat* set pixel format (required context capabilities)
    of Windows H_Dc device context. They try to set it, and eventually raise some
    exception (e.g. by CheckRequestedBufferAttributes) if it's not possible.

    SetPixelFormat_WGLChoose tries to use wglChoosePixelFormat, which is generally
    much better, more flexible, most of all: it allows to set multisampling
    parameters, which is not possible by classic ChoosePixelFormat.

    But wglChoosePixelFormat is not guaranteed to exist, so if it doesn't --- we
    fall back on classic ChoosePixelFormat (and DescribePixelFormat) by calling
    SetPixelFormat_ClassicChoose. }
  procedure SetPixelFormat_ClassicChoose;
  var
    PixelFormat: LongInt;
    pfd: Tpixelformatdescriptor;
  begin
    FillChar(pfd, SizeOf(pfd), 0);
    with pfd do
    begin
      nSize := SizeOf(TPIXELFORMATDESCRIPTOR);
      nVersion := 1;
      dwFlags := PFD_DRAW_TO_WINDOW              // Format Must Support Window
        or PFD_SUPPORT_OPENGL;                  // Format Must Support OpenGL
      if Requirements.DoubleBuffer then dwFlags := dwFlags or PFD_DOUBLEBUFFER;
      iPixelType := PFD_TYPE_RGBA;              // Request An RGBA Format
      cColorBits := Requirements.ColorBits; // WinAPI accepts here 0 as "default"
      cAlphaBits := Requirements.AlphaBits;
      cDepthBits := Requirements.DepthBits;
      cStencilBits := Requirements.StencilBits;
      { niestety cAccumRed/Green/Blue/AlphaBits sa ignorowane - musimy probowac poradzic sobie
        przy pomocy cAccumBits. }
      cAccumBits := RoundUpToMultiply(Requirements.AccumBits[0], 8) +
                    RoundUpToMultiply(Requirements.AccumBits[1], 8) +
                    RoundUpToMultiply(Requirements.AccumBits[2], 8) +
                    RoundUpToMultiply(Requirements.AccumBits[3], 8);
      iLayerType := PFD_MAIN_PLANE;             // Main Drawing Layer
    end;
    PixelFormat := Windows.ChoosePixelFormat(h_Dc, {$ifndef FPC}@{$endif}pfd);
    OSCheck( PixelFormat <> 0, 'ChoosePixelFormat');

    { sprawdzamy czy dostalismy wymagane AlphaBits, DepthBits, StencilBits i
      FAccumBits - to dlatego ze ChoosePixelFormat nie gwarantowalo nam ze dostaniemy
      rzeczywiscie to co chcemy, a w przypadku FAccumBits nie bylismy nawet w stanie
      powiedziec tego co trzeba ChoosePixelFormat.

      In the future, I may switch to using SetPixelFormat_WGLChoose by default.
      wglChoosePixelFormatARB makes CheckRequestedBufferAttributes not needed
      (as wglChoosePixelFormatARB already sensibly guarantees that GL context will
      satisfy appropriate limits).
      So this un-elegant code below will not be used (on modern Windowses / GPUs). }
    DescribePixelFormat(h_Dc, PixelFormat, SizeOf(pfd), pfd);
    Requirements.CheckRequestedBufferAttributes('ChoosePixelFormat',
      pfd.cStencilBits, pfd.cDepthBits, pfd.cAlphaBits,
      pfd.cAccumRedBits, pfd.cAccumGreenBits, pfd.cAccumBlueBits, pfd.cAccumAlphaBits,
      0 { we have to assume that ChoosePixelFormat returns context
          without multisampling abiilty });

    { skoro PixelFormat jest akceptowalny to wybierz go. Przekazywanie pfd w ponizszej
      funkcji nie jest wazne i wlasciwie moznaby z niego zrezygnowac, o ile dobrze rozumiem
      help do winapi. Wazne jest zeby przekazac wybrany PixelFormat. }
    OSCheck( SetPixelFormat(h_Dc, PixelFormat, @pfd), 'SetPixelFormat');
  end;

  procedure SetPixelFormat_WGLChoose;
  var
    Temp_h_GLRc: HGLRC;
    Temp_h_Dc: HDC;
    Temp_h_Wnd: HWND;

    { We have to create temporary window, just to query wgl. It's useless to
      call wglGetProcAddress without any GL context active.
      Yes, I know, this is utterly stupid and brain-dead to create a window
      just to query wgl extensions, but every OpenGL programmer has to do it
      (if we want to use e.g. multisampling) --- congrats M$.

      We create this temporary window with absolutely standard, minumum
      properties --- ideally, any system (supporting OpenGL at all) should
      be able to create our CreateTemporaryWindow. }

    procedure DestroyTemporaryWindow; forward;

    procedure CreateTemporaryWindow;
    var
      PixelFormat: LongInt;
      pfd: Tpixelformatdescriptor;
    begin
      Temp_h_Wnd := 0;
      Temp_h_Dc := 0;
      Temp_h_GLRc := 0;

      try
        { create Temp_H_wnd }
        Temp_H_wnd := CreateWindowExW(WS_EX_APPWINDOW or WS_EX_WINDOWEDGE,
          PWideChar(WndClassName),
          PWideChar(StringToUtf16(WindowCaption + ' - temporary window for wgl')),
          WS_OVERLAPPEDWINDOW or WS_CLIPSIBLINGS or WS_CLIPCHILDREN,
          0, 0, 100, 100,
          0 { no parent window }, 0 { no menu }, hInstance,
          nil { don't pass anything to WM_CREATE } );
        Check( Temp_H_Wnd <> 0, 'CreateWindowEx failed');

        { create Temp_h_Dc }
        Temp_h_Dc := GetDC(Temp_h_Wnd);
        Check ( Temp_h_Dc <> 0, 'GetDC failed');

        { create and set PixelFormat (must support OpenGL to be able to
          later do wglCreateContext) }
        FillChar(pfd, SizeOf(pfd), 0);
        with pfd do
        begin
          nSize := SizeOf(TPIXELFORMATDESCRIPTOR);
          nVersion := 1;
          dwFlags := PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL;
          iPixelType := PFD_TYPE_RGBA;
          iLayerType := PFD_MAIN_PLANE;
        end;
        PixelFormat := Windows.ChoosePixelFormat(Temp_h_Dc, {$ifndef FPC}@{$endif}pfd);
        OSCheck( PixelFormat <> 0, 'ChoosePixelFormat');
        OSCheck( SetPixelFormat(Temp_h_Dc, PixelFormat, @pfd), 'SetPixelFormat');

        { create and make current Temp_h_GLRc }
        Temp_h_GLRc := wglCreateContext(Temp_h_Dc);
        OSCheck( Temp_h_GLRc <> 0, 'wglCreateContext' );
        OSCheck( wglMakeCurrent(Temp_h_Dc, Temp_h_GLRc), 'wglMakeCurrent');
      except
        { make sure to finalize all partially initialized window parts }
        DestroyTemporaryWindow;
        raise;
      end;
    end;

    procedure DestroyTemporaryWindow;
    begin
      if Temp_h_GLRc <> 0 then
      begin
        wglMakeCurrent(Temp_h_Dc, 0);
        wglDeleteContext(Temp_h_GLRc);
        Temp_h_GLRc := 0;
      end;

      if Temp_h_Dc <> 0 then
      begin
        ReleaseDC(Temp_h_Wnd, Temp_h_Dc);
        Temp_h_Dc := 0;
      end;

      if Temp_h_Wnd <> 0 then
      begin
        DestroyWindow(Temp_h_Wnd);
        Temp_h_Wnd := 0;
      end;
    end;

  var
    WglExtensions: string;

    { GLExt unit doesn't provide this (although it provides related
      constants, like WGL_SAMPLE_BUFFERS_ARB). I like to check for this
      explicitly. }
    function Load_WGL_ARB_multisample: Boolean;
    begin
      Result := glext_ExtensionSupported('WGL_ARB_multisample', WglExtensions);
    end;

  var
    PixelFormat: LongInt;
    ReturnedFormats: UINT;
    VisualAttr: TLongIntList;
    VisualAttrFloat: array [0..1] of Single;
    Success: WINBOOL;
  begin
    CreateTemporaryWindow;
    try
      { Note: GLExt unit Load_Xxx procedures work with wglGetCurrentDC
        (this is passed to wglGetExtensionsStringARB call).
        That's Ok, this current context is set by our  CreateTemporaryWindow. }

      if Load_WGL_ARB_extensions_string then
      begin
        { Actually, there is no critical reason for me to check
          WGL_ARB_extensions_string (as every other Load_WGL_Xxx will
          check it for me anyway).

          1. But I want to show WglExtensions for debug purposes.
          2. And I want to implement Load_WGL_ARB_multisample, and reuse
             my acquired WglExtensions there. }

        WglExtensions := wglGetExtensionsStringARB(Temp_H_Dc);
        WritelnLog('wgl', 'wgl extensions: ' + WglExtensions);

        if Load_WGL_ARB_pixel_format then
        begin
          { Ok, wglChoosePixelFormatARB is available }

          VisualAttr := TLongIntList.Create;
          try
            VisualAttr.AddRange([
              WGL_DRAW_TO_WINDOW_ARB, GL_TRUE,
              WGL_SUPPORT_OPENGL_ARB, GL_TRUE,
              { If indexed mode will be implemented in CastleWindow one day, this can take
                WGL_TYPE_COLORINDEX_ARB instead of WGL_TYPE_RGBA_ARB. }
              WGL_PIXEL_TYPE_ARB, WGL_TYPE_RGBA_ARB,
              WGL_ACCELERATION_ARB, WGL_FULL_ACCELERATION_ARB]);
            if Requirements.DoubleBuffer then
              VisualAttr.AddRange([WGL_DOUBLE_BUFFER_ARB, GL_TRUE]);
            VisualAttr.AddRange([
              WGL_RED_BITS_ARB, Requirements.RedBits,
              WGL_GREEN_BITS_ARB, Requirements.GreenBits,
              WGL_BLUE_BITS_ARB, Requirements.BlueBits,
              WGL_DEPTH_BITS_ARB, Requirements.DepthBits,
              WGL_STENCIL_BITS_ARB, Requirements.StencilBits,
              WGL_ALPHA_BITS_ARB, Requirements.AlphaBits,
              WGL_ACCUM_RED_BITS_ARB, Requirements.AccumBits[0],
              WGL_ACCUM_GREEN_BITS_ARB, Requirements.AccumBits[1],
              WGL_ACCUM_BLUE_BITS_ARB, Requirements.AccumBits[2],
              WGL_ACCUM_ALPHA_BITS_ARB, Requirements.AccumBits[3] ]);

            if Requirements.MultiSampling > 1 then
            begin
              if Load_WGL_ARB_multisample then
              begin
                VisualAttr.AddRange([
                  WGL_SAMPLE_BUFFERS_ARB, 1,
                  WGL_SAMPLES_ARB, Requirements.MultiSampling ]);
                WritelnLog('MultiSampling', 'WGL_ARB_multisample supported, using multisampling');
              end else
                raise EGLContextNotPossible.CreateFmt('Multisampling (%d samples) ' +
                  'requested, but WGL_ARB_multisample not supported',
                  [Requirements.MultiSampling]);
            end;

            { end of VisualAttr array }
            VisualAttr.AddRange([0, 0]);

            FillChar(VisualAttrFloat, SizeOf(VisualAttrFloat), 0);

            Success := wglChoosePixelFormatARB(H_Dc, PGLint(VisualAttr.L),
              @VisualAttrFloat[0], 1, @PixelFormat, @ReturnedFormats);
          finally FreeAndNil(VisualAttr) end;

          if Success and (ReturnedFormats >= 1) then
          begin
            { We could use wglGetPixelFormatAttribivARB (equivalent to "classic"
              DescribePixelFormat) here to query context we got, and call
              CheckRequestedBufferAttributes to check whether we really got what
              we requested.

              But we don't have to: wglChoosePixelFormatARB (see
              [http://www.opengl.org/registry/specs/ARB/wgl_pixel_format.txt])
              clearly specifies which limits are "exact", which are "minimum",
              and we're actually perfectly satisfied with this.

              So, we're done now :) Just set this pixel format. }
            OSCheck( SetPixelFormat(h_Dc, PixelFormat, nil), 'SetPixelFormat');
          end else
            raise EGLContextNotPossible.CreateFmt(
              'wglChoosePixelFormatARB: pixel format with requested attributes (%s) not found',
              [ Requirements.RequestedBufferAttributes ]);
        end else
        begin
          WritelnLog('wgl', 'WGL_ARB_pixel_format not available, using classic ChoosePixelFormat');
          SetPixelFormat_ClassicChoose;
        end;
      end else
      begin
        WritelnLog('wgl', 'wglGetExtensionsStringARB not available, using classic ChoosePixelFormat');
        SetPixelFormat_ClassicChoose;
      end;
    finally DestroyTemporaryWindow end;
  end;

begin
  { Actually, everything is implemented such that I can just call
    here SetPixelFormat_WGLChoose. SetPixelFormat_WGLChoose will eventually
    fall back to SetPixelFormat_ClassicChoose, if needed.

    For now, SetPixelFormat_ClassicChoose is simply more tested, and
    SetPixelFormat_WGLChoose is needed only in case of multi-sampling.
    So, to play it safe, for view3dscene 2.4.0 and engine 1.3.0 release
    I just call SetPixelFormat_WGLChoose only if multisampling is requested.

    So in the future I may simplify this "if" to just call SetPixelFormat_WGLChoose
    always. }
  if Requirements.MultiSampling > 1 then
    SetPixelFormat_WGLChoose
  else
    SetPixelFormat_ClassicChoose;

  if (GetDeviceCaps(h_Dc, RASTERCAPS) and RC_PALETTE) <> 0 then
    raise EGLContextNotPossible.Create('This device is paletted ! Bad display settings !');

  { TODO: below we should enable context sharing.
    If WGL_ARB_create_context_profile is available, then we can use
    wglCreateContextAttribsARB instead of wglCreateContext.
    Otherwise, we still use wglCreateContext but follow with wglShareLists.
    Testcase: see if examples/window/multi_window.lpr
    shows font in all windows. }

  { create gl context and make it current }
  h_GLRc := wglCreateContext(h_Dc);
  OSCheck(h_GLRc <> 0, 'wglCreateContext');

  { All OpenGL contexts should be shared }
  if SharedContext <> nil then
    OSCheck(wglShareLists(SharedContext.h_GLRc, h_GLRc), 'wglShareLists');
end;

procedure TGLContextWGL.ContextDestroy;
begin
  if h_GLRc <> 0 then
  begin
    if (not wglMakeCurrent(h_Dc, 0)) then
      WritelnWarning('WinAPI', 'Deactivating current OpenGL rendering context (wglMakeCurrent(..., NULL)) failed.');
    if (not wglDeleteContext(h_GLRc)) then
      WritelnWarning('WinAPI', 'Releasing current OpenGL rendering context (wglDeleteContext) failed.');
    h_GLRc := 0;
  end;
end;

procedure TGLContextWGL.MakeCurrent;
begin
  Assert(h_GLRc <> 0); // window not closed
  OSCheck( wglMakeCurrent(h_Dc, h_GLRc), 'wglMakeCurrent');
end;

procedure TGLContextWGL.SwapBuffers;
begin
  Windows.SwapBuffers(h_Dc);
end;

{ TGLContextRequirements ----------------------------------------------------- }

function TGLContextRequirements.RequestedBufferAttributes: String;
begin
 if DoubleBuffer then
   Result := 'double buffered' else
   Result := 'single buffered';
 if ColorBits > 0 then
   Result := Result + Format(', with RGB colors bits (%d, %d, %d) (total %d color bits)', [RedBits, GreenBits, BlueBits, ColorBits]);
 if DepthBits > 0 then
   Result := Result + Format(', with %d-bits sized depth buffer', [DepthBits]);
 if StencilBits > 0 then
   Result := Result + Format(', with %d-bits sized stencil buffer', [StencilBits]);
 if AlphaBits > 0 then
   Result := Result + Format(', with %d-bits sized alpha channel', [AlphaBits]);
 if not AccumBits.IsZero then
   Result := Result + Format(', with (%d,%d,%d,%d)-bits sized accumulation buffer',
    [AccumBits[0], AccumBits[1], AccumBits[2], AccumBits[3]]);
 if MultiSampling > 1 then
   Result := Result + Format(', with multisampling (%d samples)', [MultiSampling]);
end;

procedure TGLContextRequirements.CheckRequestedBufferAttributes(
  const ProviderName: string; ProvidedStencilBits, ProvidedDepthBits,
  ProvidedAlphaBits, ProvidedAccumRedBits, ProvidedAccumGreenBits,
  ProvidedAccumBlueBits, ProvidedAccumAlphaBits,
  ProvidedMultiSampling: Cardinal);

  procedure CheckRequestedBits(const Name: string; RequestedBits, ProvidedBits: Cardinal);
  begin
    if ProvidedBits < RequestedBits then
      raise EGLContextNotPossible.CreateFmt('%s provided OpenGL context with %s'
        +' %d-bits sized but at least %d-bits sized is required',
        [ ProviderName, Name, ProvidedBits, RequestedBits ]);
  end;

 begin
  CheckRequestedBits('stencil buffer', StencilBits, ProvidedStencilBits);
  CheckRequestedBits('depth buffer', DepthBits, ProvidedDepthBits);
  CheckRequestedBits('alpha channel', AlphaBits, ProvidedAlphaBits);
  CheckRequestedBits('accumulation buffer''s red channel'  , AccumBits[0], ProvidedAccumRedBits);
  CheckRequestedBits('accumulation buffer''s green channel', AccumBits[1], ProvidedAccumGreenBits);
  CheckRequestedBits('accumulation buffer''s blue channel' , AccumBits[2], ProvidedAccumBlueBits);
  CheckRequestedBits('accumulation buffer''s alpha channel', AccumBits[3], ProvidedAccumAlphaBits);

  { If MultiSampling <= 1, this means that multisampling not required,
    so don't check it. Even if MultiSampling = 1 and ProvidedMultiSampling = 0
    (as most backends report no multisampling as num samples = 0), it's all Ok. }

  if MultiSampling > 1 then
  begin
    if ProvidedMultiSampling < MultiSampling then
     raise EGLContextNotPossible.CreateFmt('%s provided OpenGL context with %d ' +
       'samples for multisampling (<= 1 means that no multisampling was provided) ' +
       'but at last %d samples for multisampling is required',
       [ ProviderName, ProvidedMultiSampling, MultiSampling ]);
  end;
end;

end.
