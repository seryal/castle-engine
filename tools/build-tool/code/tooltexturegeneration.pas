{
  Copyright 2016-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Compressing and downscaling textures. }
unit ToolTextureGeneration;

{$I castleconf.inc}

interface

uses CastleUtils, CastleStringUtils,
  ToolProject;

procedure AutoGenerateTextures(const Project: TCastleProject);
procedure AutoGenerateCleanAll(const Project: TCastleProject);
procedure AutoGenerateCleanUnused(const Project: TCastleProject);

implementation

uses SysUtils,
  CastleURIUtils, CastleMaterialProperties, CastleImages, CastleFilesUtils,
  CastleLog, CastleFindFiles, CastleSoundEngine, CastleTimeUtils,
  CastleInternalAutoGenerated,
  ToolCommonUtils, ToolUtils, {SHA1,} MD5;

type
  ECannotFindTool = class(Exception)
  strict private
    FToolName: string;
  public
    constructor Create(const AToolName: string; const C: TTextureCompression);
    property ToolName: string read FToolName;
  end;

constructor ECannotFindTool.Create(const AToolName: string;
  const C: TTextureCompression);
begin
  FToolName := AToolName;
  inherited CreateFmt('Cannot find tool "%s" necessary to make compressed texture format %s',
    [ToolName, TextureCompressionToString(C)]);
end;

type
  TStats = record
    Count: Cardinal;
    HashTime: TFloatTime;
    DimensionsCount: Cardinal;
    DimensionsTime: TFloatTime;
    CompressionCount: Cardinal;
    CompressionTime: TFloatTime;
    DownscalingCount: Cardinal;
    DownscalingTime: TFloatTime;
    DxtAutoDetectCount: Cardinal;
    DxtAutoDetectTime: TFloatTime;
  end;

{ Auto-detect best DXTn compression format for this image. }
function AutoDetectDxt(const ImageUrl: string; var Stats: TStats): TTextureCompression;
var
  Image: TCastleImage;
  TimeStart: TProcessTimerResult;
begin
  Inc(Stats.DxtAutoDetectCount);
  TimeStart := ProcessTimer;

  Image := LoadImage(ImageUrl);
  try
    case Image.AlphaChannel of
      acNone    : Result:= tcDxt1_RGB;
      acTest    : Result:= tcDxt1_RGBA;
      acBlending: Result:= tcDxt5;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('Unexpected Image.AlphaChannel in AutoDetectDxt');
      {$endif}
    end;
  finally FreeAndNil(Image) end;

  Writeln('Autodetected DXTn type for "' + ImageUrl + '": ' +
    TextureCompressionToString(Result));

  Stats.DxtAutoDetectTime := Stats.DxtAutoDetectTime + TimeStart.ElapsedTime;
end;

{ Calculate file contents hash. }
function CalculateHash(const FileUrl: string; var Stats: TStats): string;
var
  TimeStart: TProcessTimerResult;
begin
  TimeStart := ProcessTimer;
  //Result := SHA1Print(SHA1File(URIToFilenameSafe(FileUrl)));
  { MD5 hash is ~2 times faster in my tests, once files are in OS cache. }
  Result := MDPrint(MDFile(URIToFilenameSafe(FileUrl), MD_VERSION_5));
  Stats.HashTime := Stats.HashTime + TimeStart.ElapsedTime;
end;

{ Make given URL relative to project's data (fails if not possible). }
function MakeUrlRelativeToData(const Project: TCastleProject; const Url: String): String;
var
  DataUrl: String;
begin
  DataUrl := FilenameToURISafe(Project.DataPath);
  if not IsPrefix(DataUrl, Url, false) then
    raise Exception.CreateFmt('File (%s) is not within data (%s)', [Url, DataUrl]);
  Result := PrefixRemove(DataUrl, Url, false);
end;

procedure AutoGenerateTextures(const Project: TCastleProject);

  procedure TryToolExe(var ToolExe: string; const ToolExeAbsolutePath: string);
  begin
    if (ToolExe = '') and RegularFileExists(ToolExeAbsolutePath) then
      ToolExe := ToolExeAbsolutePath;
  end;

  procedure TryToolExePath(var ToolExe: string; const ToolExeName: string;
    const C: TTextureCompression);
  begin
    if ToolExe = '' then
    begin
      ToolExe := FindExe(ToolExeName);
      if ToolExe = '' then
        raise ECannotFindTool.Create(ToolExeName, C);
    end;
  end;

  procedure Compressonator(const InputFile, OutputFile: string;
    const C: TTextureCompression; const CompressionNameForTool: string);
  var
    ToolExe, InputFlippedFile, OutputTempFile, TempPrefix: string;
    Image: TCastleImage;
    CommandExe: string;
    CommandOptions: TCastleStringList;
  begin
    ToolExe := '';
    { otherwise, assume it's on $PATH }
    TryToolExePath(ToolExe, 'CompressonatorCLI', C);

    TempPrefix := GetTempFileNamePrefix;

    InputFlippedFile := TempPrefix + '.png';

    { In theory, when DDSFlipped = false, we could just do
      CheckCopyFile(InputFile, InputFlippedFile).
      But then AMDCompressCLI fails to read some png files (like flying in dark_dragon).
      TODO: this comment is possibly no longer true as of
      the new (open-source and cross-platform) Compressonator. }
    Image := LoadImage(FilenameToURISafe(InputFile));
    try
      if TextureCompressionInfo[C].DDSFlipped then
        Image.FlipVertical;
      SaveImage(Image, FilenameToURISafe(InputFlippedFile));
    finally FreeAndNil(Image) end;

    { this is worse, as it requires ImageMagick }
    // RunCommandSimple(FindExe('convert'), [InputFile, '-flip', InputFlippedFile]);

    OutputTempFile := TempPrefix + 'output' + ExtractFileExt(OutputFile);

    CommandOptions := TCastleStringList.Create;
    try
      CommandExe := ToolExe;
      CommandOptions.AddRange([
        '-fd',
        CompressionNameForTool,
        InputFlippedFile,
        OutputTempFile]);

      {$ifdef UNIX}
      // CompressonatorCLI is just a bash script on Unix
      CommandOptions.Insert(0, CommandExe);
      CommandExe := '/bin/bash';
      {$endif}

      { TODO: it doesn't seem to help, DXT1_RGBA is still without
        anything useful in alpha value. Seems like AMDCompressCLI bug,
        or I just don't know how to use the DXT1 options?
        TODO: this comment is possibly no longer true as of
        the new (open-source and cross-platform) Compressonator. }
      if C = tcDxt1_RGB then // special options for tcDxt1_RGB
        CommandOptions.AddRange(
          ['-DXT1UseAlpha', '1', '-AlphaThreshold', '0.5']);

      RunCommandSimple(ExtractFilePath(TempPrefix),
        CommandExe, CommandOptions.ToArray);
    finally FreeAndNil(CommandOptions) end;

    CheckRenameFile(OutputTempFile, OutputFile);
    CheckDeleteFile(InputFlippedFile, true);
  end;

  procedure PVRTexTool(const InputFile, OutputFile: string;
    const C: TTextureCompression; const CompressionNameForTool: string);
  var
    ToolExe: string;
  begin
    ToolExe := '';
    {$ifdef UNIX}
    { Try the standard installation path on Linux.
      On x86_64, try the 64-bit version first, otherwise fallback on 32-bit. }
    {$ifdef CPU64}
    TryToolExe(ToolExe, '/opt/Imagination/PowerVR_Graphics/PowerVR_Tools/PVRTexTool/CLI/Linux_x86_64/PVRTexToolCLI');
    {$endif}
    TryToolExe(ToolExe, '/opt/Imagination/PowerVR_Graphics/PowerVR_Tools/PVRTexTool/CLI/Linux_x86_32/PVRTexToolCLI');
    {$endif}
    { otherwise, assume it's on $PATH }
    TryToolExePath(ToolExe, 'PVRTexToolCLI', C);

    RunCommandSimple(ToolExe,
      ['-f', CompressionNameForTool,
       '-q', 'pvrtcbest',
       '-m', '1',
       { On iOS, it seems that PVRTC textures must be square.
         See
         - https://en.wikipedia.org/wiki/PVRTC
         - https://developer.apple.com/library/ios/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/TextureTool/TextureTool.html
         But this is only an Apple implementation limitation, not a limitation
         of PVRTC1 compression.
         More info on this compression on
         - http://cdn.imgtec.com/sdk-documentation/PVRTC+%26+Texture+Compression.User+Guide.pdf
         - http://blog.imgtec.com/powervr/pvrtc2-taking-texture-compression-to-a-new-dimension

         In practice, forcing texture here to be square is very bad:
         - If a texture is addressed from the top, e.g. in Spine atlas file,
           then it's broken now. So using a texture atlases like 1024x512 from Spine
           would be broken.
         - ... and there's no sensible solution to the above problem.
           We could shift the texture, but then what if something addresses
           it from the bottom?
         - What if something (VRML/X3D or Collada texture coords) addresses
           texture in 0...1 range?
         - To fully work with it, we would have to store original texture
           size somewhere, and it's shift with regards to new compressed texture,
           and support it everywhere where we "interpret" texture coordinates
           (like when reading Spine atlas, or in shaders when sampling
           texture coordinates). Absolutely ugly.

         So, don't do this! Allow rectangular PVRTC textures!
       }
       // '-squarecanvas', '+' ,

       { TODO: use "-flip y" only when
         - TextureCompressionInfo[C].DDSFlipped (it is false for DXTn)
         - OutputFile is DDS.

         If OutputFile is KTX, then always use
         '-flip' 'y,flag'
         which means that file should be ordered bottom-to-top (and marked as such
         in the KTX header). This means it can be read in an efficient way.
         Using KTX requires some improvements to CastleAutoGenerated.xml
         first (to mark that we were able to generate KTX).
       }
       '-flip', 'y',

       '-i', InputFile,
       '-o', OutputFile]);
  end;

  procedure NVCompress(const InputFile, OutputFile: string;
    const C: TTextureCompression; const CompressionNameForTool: string);
  var
    ToolExe: string;
  begin
    ToolExe := '';

    { assume it's on $PATH }
    TryToolExePath(ToolExe, 'nvcompress', C);

    RunCommandSimple(ToolExe,
      ['-' + CompressionNameForTool,
       InputFile,
       OutputFile]);
  end;

  procedure NVCompress_FallbackCompressonator(
    const InputFile, OutputFile: string;
    const C: TTextureCompression;
    const CompressionNameForNVCompress,
          CompressionNameForCompressonator: string);
  begin
    try
      NVCompress(InputFile, OutputFile, C, CompressionNameForNVCompress);
      Exit; // if there was no ECannotFindTool exception, then success: exit
    except
      on E: ECannotFindTool do
        Writeln('Cannot find nvcompress executable. Falling back to Compressonator.');
    end;

    Compressonator(InputFile, OutputFile, C, CompressionNameForCompressonator);
  end;

  { Convert both URLs to filenames and check whether output should be updated.
    In any case, makes appropriate message to user.
    If the file needs to be updated, makes sure it's output directory exists. }
  function CheckNeedsUpdate(const InputURL, OutputURL: string; out InputFile, OutputFile: string;
    const ContentAlreadyProcessed: boolean): boolean;
  begin
    InputFile := URIToFilenameSafe(InputURL);
    OutputFile := URIToFilenameSafe(OutputURL);

    { Previously, instead of checking "not ContentAlreadyProcessed",
      we were checking modification times:
      "(FileAge(OutputFile) < FileAge(InputFile))".
      But this was not working perfectly -- updating files from version control
      makes the modification times not-100%-reliable for this. }

    Result := (not RegularFileExists(OutputFile)) or (not ContentAlreadyProcessed);
    if Result then
    begin
      Writeln(Format('Updating "%s" from input "%s"', [OutputFile, InputFile]));
      CheckForceDirectories(ExtractFilePath(OutputFile));
    end else
    begin
      if Verbose then
        Writeln(Format('No need to update "%s"', [OutputFile]));
    end;
  end;

  procedure UpdateTextureScale(const InputURL, OutputURL: string;
    const Scale: Cardinal; var Stats: TStats;
    const ContentAlreadyProcessed: boolean);
  const
    // equivalent of GLTextureMinSize, but for TextureLoadingScale, not for GLTextureScale
    TextureMinSize = 16;
  var
    InputFile, OutputFile: string;
    Image: TCastleImage;
    NewWidth, NewHeight: Integer;
    NewScale: Cardinal;
    TimeStart: TProcessTimerResult;
  begin
    if CheckNeedsUpdate(InputURL, OutputURL, InputFile, OutputFile, ContentAlreadyProcessed) then
    begin
      Inc(Stats.DownscalingCount);
      TimeStart := ProcessTimer;

      Image := LoadImage(InputURL);
      try
        NewWidth := Image.Width;
        NewHeight := Image.Height;
        NewScale := 1;
        while (NewWidth shr 1 >= TextureMinSize) and
              (NewHeight shr 1 >= TextureMinSize) and
              (NewScale < Scale) do
        begin
          NewWidth := NewWidth shr 1;
          NewHeight := NewHeight shr 1;
          Inc(NewScale);
        end;
        if Verbose then
          Writeln(Format('Resizing "%s" from %dx%d to %dx%d',
            [InputURL, Image.Width, Image.Height, NewWidth, NewHeight]));
        Image.Resize(NewWidth, NewHeight, BestInterpolation);
        SaveImage(Image, OutputURL);
      finally FreeAndNil(Image) end;

      Stats.DownscalingTime := Stats.DownscalingTime + TimeStart.ElapsedTime;
    end;
  end;

  { Like UpdateTextureScale, and also record the output in AutoGeneratedTex.Generated }
  procedure UpdateTextureScaleWhole(
    const AutoGeneratedTex: TAutoGenerated.TTexture;
    const InputURL, OutputURL: string;
    const Scale: Cardinal; var Stats: TStats;
    const ContentAlreadyProcessed: boolean);
  var
    Generated: TAutoGenerated.TGeneratedTexture;
  begin
    UpdateTextureScale(InputURL, OutputURL, Scale, Stats, ContentAlreadyProcessed);

    { Using Low(TTextureCompression), it should not matter when Compression = false. }
    Generated := AutoGeneratedTex.Generated(false, Low(TTextureCompression), Scale);
    Generated.URL := MakeUrlRelativeToData(Project, OutputURL);
    { Only downscaled textures are packed for all platforms now }
    Generated.Platforms := AllPlatforms;
  end;

  procedure UpdateTextureCompress(const InputURL, OutputURL: string;
    const C: TTextureCompression; var Stats: TStats;
    const ContentAlreadyProcessed: boolean);
  var
    InputFile, OutputFile: string;
    TimeStart: TProcessTimerResult;
  begin
    if CheckNeedsUpdate(InputURL, OutputURL, InputFile, OutputFile, ContentAlreadyProcessed) then
    begin
      Inc(Stats.CompressionCount);
      TimeStart := ProcessTimer;

      case C of
        { For Compressonator DXT1:
          We have special handling for C = tcDxt1_RGB versus tcDxt1_RGBA,
          they will be handled differently, even though they are both called 'DXT1'. }
        tcDxt1_RGB : NVCompress_FallbackCompressonator(InputFile, OutputFile, C, 'bc1' , 'DXT1');
        tcDxt1_RGBA: NVCompress_FallbackCompressonator(InputFile, OutputFile, C, 'bc1a', 'DXT1');
        tcDxt3     : NVCompress_FallbackCompressonator(InputFile, OutputFile, C, 'bc2' , 'DXT3');
        tcDxt5     : NVCompress_FallbackCompressonator(InputFile, OutputFile, C, 'bc3' , 'DXT5');

        tcATITC_RGB                   : Compressonator(InputFile, OutputFile, C, 'ATC_RGB'              );
        tcATITC_RGBA_InterpolatedAlpha: Compressonator(InputFile, OutputFile, C, 'ATC_RGBA_Interpolated');
        tcATITC_RGBA_ExplicitAlpha    : Compressonator(InputFile, OutputFile, C, 'ATC_RGBA_Explicit'    );

        tcPvrtc1_4bpp_RGB:  PVRTexTool(InputFile, OutputFile, C, 'PVRTC1_4_RGB');
        tcPvrtc1_2bpp_RGB:  PVRTexTool(InputFile, OutputFile, C, 'PVRTC1_2_RGB');
        tcPvrtc1_4bpp_RGBA: PVRTexTool(InputFile, OutputFile, C, 'PVRTC1_4');
        tcPvrtc1_2bpp_RGBA: PVRTexTool(InputFile, OutputFile, C, 'PVRTC1_2');
        tcPvrtc2_4bpp:      PVRTexTool(InputFile, OutputFile, C, 'PVRTC2_4');
        tcPvrtc2_2bpp:      PVRTexTool(InputFile, OutputFile, C, 'PVRTC2_2');

        tcETC1:             PVRTexTool(InputFile, OutputFile, C, 'ETC1');
                      // or Compressonator(InputFile, OutputFile, C, 'ETC_RGB');
        tcASTC_4x4_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_4x4');
        tcASTC_5x4_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_5x4');
        tcASTC_5x5_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_5x5');
        tcASTC_6x5_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_6x5');
        tcASTC_6x6_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_6x6');
        tcASTC_8x5_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x5');
        tcASTC_8x6_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x6');
        tcASTC_8x8_RGBA:           PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x8');
        tcASTC_10x5_RGBA:          PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x5');
        tcASTC_10x6_RGBA:          PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x6');
        tcASTC_10x8_RGBA:          PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x8');
        tcASTC_10x10_RGBA:         PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x10');
        tcASTC_12x10_RGBA:         PVRTexTool(InputFile, OutputFile, C, 'ASTC_12x10');
        tcASTC_12x12_RGBA:         PVRTexTool(InputFile, OutputFile, C, 'ASTC_12x12');
        tcASTC_4x4_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_4x4,UBN,sRGB');
        tcASTC_5x4_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_5x4,UBN,sRGB');
        tcASTC_5x5_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_5x5,UBN,sRGB');
        tcASTC_6x5_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_6x5,UBN,sRGB');
        tcASTC_6x6_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_6x6,UBN,sRGB');
        tcASTC_8x5_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x5,UBN,sRGB');
        tcASTC_8x6_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x6,UBN,sRGB');
        tcASTC_8x8_SRGB8_ALPHA8:   PVRTexTool(InputFile, OutputFile, C, 'ASTC_8x8,UBN,sRGB');
        tcASTC_10x5_SRGB8_ALPHA8:  PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x5,UBN,sRGB');
        tcASTC_10x6_SRGB8_ALPHA8:  PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x6,UBN,sRGB');
        tcASTC_10x8_SRGB8_ALPHA8:  PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x8,UBN,sRGB');
        tcASTC_10x10_SRGB8_ALPHA8: PVRTexTool(InputFile, OutputFile, C, 'ASTC_10x10,UBN,sRGB');
        tcASTC_12x10_SRGB8_ALPHA8: PVRTexTool(InputFile, OutputFile, C, 'ASTC_12x10,UBN,sRGB');
        tcASTC_12x12_SRGB8_ALPHA8: PVRTexTool(InputFile, OutputFile, C, 'ASTC_12x12,UBN,sRGB');

        {$ifndef COMPILER_CASE_ANALYSIS}
        else WritelnWarning('GPUCompression', Format('Compressing to GPU format %s not implemented (to update "%s")',
          [TextureCompressionToString(C), OutputFile]));
        {$endif}
      end;

      Stats.CompressionTime := Stats.CompressionTime + TimeStart.ElapsedTime;
    end;
  end;

  { Read texture sizes, place them in TAutoGenerated.TTexture fields. }
  procedure UpdateTextureDimensions(const AutoGeneratedTex: TAutoGenerated.TTexture;
    const TextureUrl: String; var Stats: TStats);
  var
    Image: TCastleImage;
    TimeStart: TProcessTimerResult;
  begin
    Inc(Stats.DimensionsCount);
    TimeStart := ProcessTimer;

    Image := LoadImage(TextureUrl);
    try
      AutoGeneratedTex.Width := Image.Width;
      AutoGeneratedTex.Height := Image.Height;
      AutoGeneratedTex.Depth := Image.Depth;
    finally FreeAndNil(Image) end;

    Stats.DimensionsTime := Stats.DimensionsTime + TimeStart.ElapsedTime;
  end;

  { Like UpdateTextureCompress, and also record the output in AutoGeneratedTex.Generated }
  procedure UpdateTextureCompressWhole(const MatProps: TMaterialProperties;
    const AutoGeneratedTex: TAutoGenerated.TTexture;
    const C: TTextureCompression;
    const OriginalTextureURL, UncompressedURL: String;
    const Scale: Cardinal;
    var Stats: TStats;
    const ContentAlreadyProcessed: Boolean;
    const Platforms: TCastlePlatforms);
  var
    CompressedURL: string;
    Generated: TAutoGenerated.TGeneratedTexture;
  begin
    CompressedURL := MatProps.AutoGeneratedTextureURL(OriginalTextureURL, true, C, Scale);
    { We use the UncompressedURL that was updated previously.
      This way there's no need to scale the texture here. }
    UpdateTextureCompress(UncompressedURL, CompressedURL, C, Stats, ContentAlreadyProcessed);

    Generated := AutoGeneratedTex.Generated(true, C, Scale);
    Generated.URL := MakeUrlRelativeToData(Project, CompressedURL);
    Generated.Platforms := Platforms;
  end;

  procedure UpdateTexture(const MatProps: TMaterialProperties;
    const OriginalTextureURL: String; var Stats: TStats;
    const AutoGenerated: TAutoGenerated);
  var
    UncompressedURL: string;
    C: TTextureCompression;
    Scale: Cardinal;
    ToGenerate: TTextureCompressionsToGenerate;
    Compressions: TCompressionsMap;
    CompressionPair: TCompressionsMap.TDictionaryPair;
    RelativeOriginalTextureUrl, Hash: string;
    ContentAlreadyProcessed: boolean;
    AutoGeneratedTex: TAutoGenerated.TTexture;
  begin
    Inc(Stats.Count);

    Hash := CalculateHash(OriginalTextureURL, Stats);

    // calculate and compare Hash with AutoGenerated
    RelativeOriginalTextureUrl := MakeUrlRelativeToData(Project, OriginalTextureUrl);
    AutoGeneratedTex := AutoGenerated.Texture(RelativeOriginalTextureUrl, 'Desktop', true);
    ContentAlreadyProcessed := AutoGeneratedTex.Hash = Hash;

    { We could just Exit now if ContentAlreadyProcessed.
      But it's safer to continue, and check do the indicated (generated) files exist.
      If not, we will generate them, even when hash was already OK. }

    if (not ContentAlreadyProcessed) or
       { old filed before we added dimensions }
       ( (AutoGeneratedTex.Width = 0) and
         (AutoGeneratedTex.Height = 0) and
         (AutoGeneratedTex.Depth = 0) ) then
    begin
      // store new Hash in AutoGenerated
      AutoGeneratedTex.Hash := Hash;
      UpdateTextureDimensions(AutoGeneratedTex, OriginalTextureURL, Stats);
    end;

    for Scale in MatProps.AutoScale(OriginalTextureURL) do
    begin
      if (Scale <> 1) or MatProps.TrivialUncompressedConvert(OriginalTextureURL) then
      begin
        UncompressedURL := MatProps.AutoGeneratedTextureURL(OriginalTextureURL, false, Low(TTextureCompression), Scale);
        UpdateTextureScaleWhole(AutoGeneratedTex, OriginalTextureURL, UncompressedURL, Scale, Stats, ContentAlreadyProcessed);
      end else
        UncompressedURL := OriginalTextureURL;

      ToGenerate := MatProps.AutoCompressedTextureFormats(OriginalTextureURL);
      if ToGenerate <> nil then
      begin
        Compressions := ToGenerate.Compressions;

        { TODO: we perform AutoDetectDxt call every time.
          Instead, information in auto_generated.xml could allow us to avoid it. }
        if ToGenerate.DxtAutoDetect then
        begin
          C := AutoDetectDxt(OriginalTextureURL, Stats);
          UpdateTextureCompressWhole(MatProps, AutoGeneratedTex, C, OriginalTextureURL, UncompressedURL, Scale, Stats, ContentAlreadyProcessed,
            ToGenerate.DxtAutoDetectPlatforms);
        end;

        for CompressionPair in Compressions do
        begin
          C := CompressionPair.Key;
          UpdateTextureCompressWhole(MatProps, AutoGeneratedTex, C, OriginalTextureURL, UncompressedURL, Scale, Stats, ContentAlreadyProcessed,
            CompressionPair.Value);
        end;
      end;
    end;
  end;

var
  Textures: TCastleStringList;
  I: Integer;
  AutoGeneratedUrl, MatPropsUrl: string;
  MatProps: TMaterialProperties;
  Stats: TStats;
  AutoGenerated: TAutoGenerated;
begin
  if not Project.DataExists then
  begin
    WritelnVerbose('Material properties file does not exist in data (because <data exists="false"/> in CastleEngineManifest.xml), so not compressing anything.');
    Exit;
  end;

  MatPropsUrl := FilenameToURISafe(Project.DataPath + 'material_properties.xml');
  if not URIFileExists(MatPropsUrl) then
  begin
    WritelnVerbose('Material properties file does not exist, so not compressing anything: ' + MatPropsUrl);
    Exit;
  end;

  FillChar(Stats, SizeOf(Stats), 0);

  AutoGeneratedUrl := FilenameToURISafe(Project.DataPath + TAutoGenerated.FileName);
  AutoGenerated := TAutoGenerated.Create;
  try
    AutoGenerated.LoadFromFile(AutoGeneratedUrl);

    MatProps := TMaterialProperties.Create(false);
    try
      MatProps.URL := MatPropsUrl;
      Textures := MatProps.AutoGeneratedTextures;
      try
        for I := 0 to Textures.Count - 1 do
          UpdateTexture(MatProps, Textures[I], Stats, AutoGenerated);
      finally FreeAndNil(Textures) end;
    finally FreeAndNil(MatProps) end;

    AutoGenerated.CleanNotExisting(FilenameToURISafe(Project.DataPath), true);
    AutoGenerated.SaveToFile(AutoGeneratedUrl);
  finally FreeAndNil(AutoGenerated) end;

  Write(Format(
    'Automatic texture generation completed:' + NL +
    '  %d textures considered to be compressed and/or downscaled.' + NL +
    '  Hashes calculation time: %f seconds.' + NL +
    '  Dimensions calculations: %d in %f seconds.' + NL +
    '  Compressions done: %d in %f seconds.' + NL +
    '  Downscaling done: %d in %f seconds.' + NL +
    '  DXTn auto-detection done: %d in %f seconds.' + NL, [
    Stats.Count,
    Stats.HashTime,
    Stats.DimensionsCount,
    Stats.DimensionsTime,
    Stats.CompressionCount,
    Stats.CompressionTime,
    Stats.DownscalingCount,
    Stats.DownscalingTime,
    Stats.DxtAutoDetectCount,
    Stats.DxtAutoDetectTime
  ]));
end;

procedure CleanDir(const FileInfo: TFileInfo; Data: Pointer;
  var StopSearch: boolean);
begin
  Writeln('Deleting ', FileInfo.AbsoluteName);
  RemoveNonEmptyDir(FileInfo.AbsoluteName);
end;

procedure AutoGenerateCleanAll(const Project: TCastleProject);

  procedure TryDeleteFile(const FileName: string);
  begin
    if RegularFileExists(FileName) then
    begin
      Writeln('Deleting ' + FileName);
      CheckDeleteFile(FileName);
    end;
  end;

begin
  if Project.DataExists then
  begin
    FindFiles(Project.DataPath, TAutoGenerated.AutoGeneratedDirName, true,
      @CleanDir, nil, [ffRecursive]);

    TryDeleteFile(Project.DataPath + TAutoGenerated.FileName);
  end;
end;

type
  TAutoGeneratedCleanUnusedHandler = class
    Project: TCastleProject;
    AutoGenerated: TAutoGenerated;
    destructor Destroy; override;
    procedure FindFilesCallback(const FileInfo: TFileInfo; var StopSearch: boolean);
  end;

procedure TAutoGeneratedCleanUnusedHandler.FindFilesCallback(
  const FileInfo: TFileInfo; var StopSearch: boolean);
var
  UrlInData: String;
begin
  UrlInData := ExtractRelativePath(Project.DataPath, FileInfo.AbsoluteName);
  UrlInData := StringReplace(UrlInData, '\', '/', [rfReplaceAll]);

  if (Pos('/' + TAutoGenerated.AutoGeneratedDirName + '/', UrlInData) <> 0) and
     (not AutoGenerated.Used(UrlInData)) then
  begin
    WritelnVerbose('Deleting unused ' + FileInfo.AbsoluteName);
    CheckDeleteFile(FileInfo.AbsoluteName, true);
  end;
end;

destructor TAutoGeneratedCleanUnusedHandler.Destroy;
begin
  FreeAndNil(AutoGenerated);
  inherited;
end;

procedure AutoGenerateCleanUnused(const Project: TCastleProject);
var
  AutoGeneratedUrl: String;
  Handler: TAutoGeneratedCleanUnusedHandler;
begin
  if Project.DataExists then
  begin
    Handler := TAutoGeneratedCleanUnusedHandler.Create;
    try
      Handler.Project := Project;

      AutoGeneratedUrl := FilenameToURISafe(Project.DataPath + TAutoGenerated.FileName);
      Handler.AutoGenerated := TAutoGenerated.Create;
      Handler.AutoGenerated.LoadFromFile(AutoGeneratedUrl);

      FindFiles(Project.DataPath, '*', false, @Handler.FindFilesCallback, [ffRecursive]);
    finally FreeAndNil(Handler) end;
  end;
end;

end.
