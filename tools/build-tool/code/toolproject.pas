{
  Copyright 2014-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Project information (from CastleEngineManifest.xml) and operations. }
unit ToolProject;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Generics.Collections,
  CastleFindFiles, CastleStringUtils, CastleUtils,
  ToolArchitectures, ToolCompile, ToolUtils, ToolServices, ToolAssocDocTypes,
  ToolPackage, ToolManifest;

type
  ECannotGuessManifest = class(Exception);

  TCastleProject = class
  private
    ManifestFile: string;
    Manifest: TCastleManifest;
    DeletedFiles: Cardinal; //< only for DeleteFoundFile
    // Helpers only for ExtractTemplateFoundFile.
    // @groupBegin
    ExtractTemplateDestinationPath, ExtractTemplateDir: string;
    ExtractTemplateOverrideExisting: Boolean;
    // @groupEnd
    { Use to define macros containing the Android architecture names.
      Must be set by all commands that may use our macro system. }
    AndroidCPUS: TCPUS;
    IOSExportMethod: String; // set by DoPackage based on PackageFormat, otherwise ''
    procedure DeleteFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);
    function PackageName(const OS: TOS; const CPU: TCPU; const PackageFormat: TPackageFormatNoDefault;
      const PackageNameIncludeVersion: Boolean): string;
    function SourcePackageName(const PackageNameIncludeVersion: Boolean): string;
    procedure ExtractTemplateFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);

    { Convert Name to a valid Pascal identifier. }
    function NamePascal: string;

    { Extract a single file using the template system.
      SourceFileName and DestinationFileName should be absolute filenames
      of source and destination files.
      DestinationRelativeFileName should be a relative version of DestinationFileName,
      relative to the template root.

      This is used internally by ExtractTemplateFoundFile, which is in turn used
      by ExtractTemplate that can extract a whole template directory.

      It can also be used directly to expand a single file. }
    procedure ExtractTemplateFile(
      const SourceFileName, DestinationFileName, DestinationRelativeFileName: string;
      const OverrideExisting: boolean);

    { Generate a program/library file from template. }
    procedure GeneratedSourceFile(
      const TemplateRelativeURL, TargetRelativePath, ErrorMessageMissingGameUnits: string;
      const CreateIfNecessary: boolean;
      out RelativeResult, AbsoluteResult: string);
    procedure GeneratedSourceFile(
      const TemplateRelativeURL, TargetRelativePath, ErrorMessageMissingGameUnits: string;
      const CreateIfNecessary: boolean);

    function AndroidSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
    function IOSSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
    function NXSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
    function StandaloneSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
    function PluginSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
    function PluginLibraryFile(const OS: TOS; const CPU: TCPU): string;

    procedure AddMacrosAndroid(const Macros: TStringStringMap);
    procedure AddMacrosIOS(const Macros: TStringStringMap);
  public
    constructor Create;
    constructor Create(const APath: string);
    destructor Destroy; override;

    { Commands on a project, used by the main program code. }
    { }

    procedure DoCreateManifest;
    procedure DoCompile(const Target: TTarget; const OS: TOS; const CPU: TCPU;
      const Plugin: boolean; const Mode: TCompilationMode; const FpcExtraOptions: TStrings = nil);
    procedure DoPackage(const Target: TTarget;
      const OS: TOS; const CPU: TCPU; const Plugin: boolean; const Mode: TCompilationMode;
      const PackageFormat: TPackageFormat;
      const PackageNameIncludeVersion, UpdateOnlyCode: Boolean);
    procedure DoInstall(const Target: TTarget; const OS: TOS; const CPU: TCPU;
      const Plugin: boolean);
    procedure DoRun(const Target: TTarget; const OS: TOS; const CPU: TCPU;
      const Plugin: boolean; const Params: TCastleStringList);
    procedure DoPackageSource(
      const PackageFormat: TPackageFormat;
      const PackageNameIncludeVersion: Boolean);
    procedure DoClean;
    procedure DoAutoGenerateTextures;
    procedure DoAutoGenerateClean(const CleanAll: Boolean);
    procedure DoGenerateProgram;
    procedure DoEditor;

    { Information about the project, derived from CastleEngineManifest.xml. }
    { }

    function Version: TProjectVersion;
    function QualifiedName: string;
    function Dependencies: TDependencies;
    function Name: string;
    { Project path. Always ends with path delimiter, like a slash or backslash. }
    function Path: string;
    function DataExists: Boolean;
    { Project data path. Always ends with path delimiter, like a slash or backslash.
      Should be ignored if not @link(DataExists). }
    function DataPath: string;
    function Caption: string;
    function Author: string;
    function ExecutableName: string;
    function FullscreenImmersive: boolean;
    function ScreenOrientation: TScreenOrientation;
    function AndroidCompileSdkVersion: Cardinal;
    function AndroidMinSdkVersion: Cardinal;
    function AndroidTargetSdkVersion: Cardinal;
    function AndroidProjectType: TAndroidProjectType;
    function Icons: TImageFileNames;
    function LaunchImages: TImageFileNames;
    function SearchPaths: TStringList;
    function LibraryPaths: TStringList;
    function AndroidServices: TServiceList;
    function IOSServices: TServiceList;
    function AssociateDocumentTypes: TAssociatedDocTypeList;
    function ListLocalizedAppName: TListLocalizedAppName;

    { List filenames of external libraries used by the current project,
      on given OS/CPU. }
    procedure ExternalLibraries(const OS: TOS; const CPU: TCPU; const List: TStrings;
      const CheckFilesExistence: Boolean = true);

    function ReplaceMacros(const Source: string): string;

    { Recursively copy a directory from TemplatePath (this is relative
      to the build tool data) to the DestinationPath (this should be an absolute
      existing directory name).

      Each file is processed by the ReplaceMacros method.

      OverrideExisting says what happens when the destination file already exists.

      - OverrideExisting = @false (default) means that the
        destination file will be left unchanged
        (to preserve possible user customization),
        or source will be merged into destination
        (in case of special filenames;
        this allows to e.g. merge AndroidManifest.xml).

      - OverrideExisting = @true means that the destination file
        will simply be overridden, without any warning, without
        any merging.
    }
    procedure ExtractTemplate(const TemplatePath, DestinationPath: string;
      const OverrideExisting: Boolean = false);

    { Output Android library resulting from compilation.
      Relative to @link(Path) if AbsolutePath = @false,
      otherwise a complete absolute path.

      CPU should be one of CPUs supported on Android platform (arm, aarch64)
      or cpuNone to get the library name without the CPU suffix. }
    function AndroidLibraryFile(const CPU: TCPU; const AbsolutePath: boolean = true): string;

    { Get platform-independent files that should be included in a package,
      remove files that should be excluded.

      If OnlyData, then only takes stuff inside DataPath,
      and Files will contain URLs relative to DataPath.
      Otherwise, takes all files to be packaged in a project,
      and Files will contain URLs relative to @link(Path).

      The copy will only contain files useful on given TargetPlatform.
      Right now this means we will exclude auto-generated textures not suitable
      for TargetPlatform. }
    function PackageFiles(const OnlyData: boolean;
      const TargetPlatform: TCastlePlatform): TCastleStringList;

    { Output iOS library resulting from compilation.
      Relative to @link(Path) if AbsolutePath = @false,
      otherwise a complete absolute path. }
    function IOSLibraryFile(const AbsolutePath: boolean = true): string;

    { Output Nintendo Switch library resulting from compilation.
      Relative to @link(Path) if AbsolutePath = @false,
      otherwise a complete absolute path. }
    function NXLibraryFile(const AbsolutePath: boolean = true): string;

    { Where should we place our output files, calculated looking at OutputPathBase
      and project path. Always an absolute filename ending with path delimiter. }
    function OutputPath: string;

    { Copy project data subdirectory to given path.
      OutputDataPath may but doesn't have to end with PathDelim.

      The path will be created if necessary (even if there are no files,
      this is useful at least for XCode as it references the resulting directory,
      so it must exist).

      The copy will only contain files useful on given TargetPlatform.
      Right now this means we will exclude auto-generated textures not suitable
      for TargetPlatform.

      We also generate the auto_generated/CastleDataInformation.xml inside.
      (Actually, this means the resulting directory is never empty now.) }
    procedure CopyData(OutputDataPath: string; const TargetPlatform: TCastlePlatform);

    { Is this filename created by some DoPackage or DoPackageSource command.
      FileName must be relative to project root directory. }
    function PackageOutput(const FileName: String): Boolean;
  end;

implementation

uses StrUtils, DOM, Process,
  CastleURIUtils, CastleXMLUtils, CastleLog, CastleFilesUtils,
  ToolResources, ToolAndroid, ToolWindowsRegistry,
  ToolTextureGeneration, ToolIOS, ToolAndroidMerging, ToolNintendoSwitch,
  ToolCommonUtils, ToolMacros, ToolCompilerInfo, ToolPackageCollectFiles;

const
  SErrDataDir = 'Make sure you have installed the data files of the Castle Game Engine build tool. Usually it is easiest to set the $CASTLE_ENGINE_PATH environment variable to the location of castle_game_engine/ or castle-engine/ directory, the build tool will then find its data correctly.'
    {$ifdef UNIX}
    + ' Or place the data in system-wide location /usr/share/castle-engine/ or /usr/local/share/castle-engine/.'
    {$endif};

{ Insert 'lib' prefix at the beginning of file name. }
function InsertLibPrefix(const S: string): string;
begin
  Result := ExtractFilePath(S) + 'lib' + ExtractFileName(S);
end;

{ Compiled library name (.so, .dll etc.) from given source code filename. }
function CompiledLibraryFile(const S: string; const OS: TOS): string;
begin
  Result := ChangeFileExt(S, LibraryExtensionOS(OS));
  if OS in AllUnixOSes then
    Result := InsertLibPrefix(Result);
end;

{ TCastleProject ------------------------------------------------------------- }

constructor TCastleProject.Create;
var
  { look for CastleEngineManifest.xml in this dir, or parents }
  Dir, ParentDir: string;
begin
  Dir := GetCurrentDir;
  while not RegularFileExists(InclPathDelim(Dir) + ManifestName) do
  begin
    ParentDir := ExtractFileDir(ExclPathDelim(Dir));
    if (ParentDir = '') or (ParentDir = Dir) then
    begin
      { no parent directory, give up, assume auto-guessed values in current dir }
      Create(GetCurrentDir);
      Exit;
    end;
    {if Verbose then
      Writeln('Manifest not found, looking in parent directory: ', ParentDir);}
    Dir := ParentDir;
  end;
  Create(Dir);
end;

constructor TCastleProject.Create(const APath: string);

  procedure ReadManifest;

    function GuessName: string;
    var
      FileInfo: TFileInfo;
    begin
      Result := ExtractFileName(ExtractFileDir(ManifestFile));
      if not RegularFileExists(Result + '.lpr') then
      begin
        if FindFirstFile(GetCurrentDir, '*.lpr', false, [], FileInfo) then
          Result := DeleteFileExt(FileInfo.Name)
        else
        if FindFirstFile(GetCurrentDir, '*.dpr', false, [], FileInfo) then
          Result := DeleteFileExt(FileInfo.Name)
        else
          raise ECannotGuessManifest.Create('Cannot find any *.lpr or *.dpr file in this directory, cannot guess which file to compile.' + NL +
            'Please create a CastleEngineManifest.xml to instruct Castle Game Engine build tool how to build your project.');
      end;
    end;

  var
    ManifestUrl: string;
  begin
    ManifestFile := InclPathDelim(APath) + ManifestName;
    ManifestUrl := FilenameToURISafe(ManifestFile);

    if not RegularFileExists(ManifestFile) then
    begin
      Writeln('Manifest file not found: ' + ManifestFile);
      Writeln('Guessing project values. Use create-manifest command to write these guesses into new CastleEngineManifest.xml');
      Manifest := TCastleManifest.CreateGuess(APath, GuessName);
    end else
    begin
      WritelnVerbose('Manifest file found: ' + ManifestFile);
      Manifest := TCastleManifest.CreateFromUrl(APath, ManifestUrl);
    end;
  end;

  function DependenciesToStr(const S: TDependencies): string;
  var
    D: TDependency;
  begin
    Result := '';
    for D in S do
    begin
      if Result <> '' then Result += ', ';
      Result += DependencyToString(D);
    end;
    Result := '[' + Result + ']';
  end;

begin
  inherited Create;

  ReadManifest;

  if Verbose then
    Writeln('Project "' + Name + '" dependencies: ' + DependenciesToStr(Dependencies));
end;

destructor TCastleProject.Destroy;
begin
  FreeAndNil(Manifest);
  inherited;
end;

procedure TCastleProject.DoCreateManifest;
var
  Contents: string;
begin
  if RegularFileExists(ManifestFile) then
    raise Exception.CreateFmt('Manifest file "%s" already exists, refusing to overwrite it',
      [ManifestFile]);
  Contents := '<?xml version="1.0" encoding="utf-8"?>' +NL+
'<project name="' + Name + '" standalone_source="' + Manifest.StandaloneSource + '">' +NL+
'</project>' + NL;
  StringToFile(ManifestFile, Contents);
  Writeln('Created manifest ' + ManifestFile);
end;

procedure TCastleProject.DoCompile(const Target: TTarget;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean; const Mode: TCompilationMode;
  const FpcExtraOptions: TStrings);

  { Copy external libraries to LibrariesOutputPath.
    LibrariesOutputPath must be empty (current dir) or ending with path delimiter. }
  procedure AddExternalLibraries(const LibrariesOutputPath: String);
  var
    List: TCastleStringList;
    OutputFile, FileName: String;
  begin
    List := TCastleStringList.Create;
    try
      ExternalLibraries(OS, CPU, List);
      for FileName in List do
      begin
        OutputFile := LibrariesOutputPath + ExtractFileName(FileName);
        WritelnVerbose('Copying library to ' + OutputFile);
        CheckCopyFile(FileName, OutputFile);
      end;
    finally FreeAndNil(List) end;
  end;

var
  SourceExe, DestExe, MainSource: string;
  ExtraOptions: TCastleStringList;
begin
  Writeln(Format('Compiling project "%s" for %s in mode "%s".',
    [Name, TargetCompleteToString(Target, OS, CPU, Plugin), ModeToString(Mode)]));

  if Manifest.BuildUsingLazbuild then
  begin
    CompileLazbuild(OS, CPU, Mode, Path, Manifest.LazarusProject);
    Exit;
  end;

  ExtraOptions := TCastleStringList.Create;
  try
    ExtraOptions.AddRange(Manifest.ExtraCompilerOptions);
    if FpcExtraOptions <> nil then
      ExtraOptions.AddRange(FpcExtraOptions);

    case Target of
      targetAndroid:
        begin
          CompileAndroid(Self, Mode, Path, AndroidSourceFile(true, true),
            SearchPaths, LibraryPaths, ExtraOptions);
        end;
      targetIOS:
        begin
          CompileIOS(Mode, Path, IOSSourceFile(true, true),
            SearchPaths, LibraryPaths, ExtraOptions);
          LinkIOSLibrary(Path, IOSLibraryFile);
          Writeln('Compiled library for iOS in ', IOSLibraryFile(false));
        end;
      targetNintendoSwitch:
        begin
          CompileNintendoSwitchLibrary(Self, Mode, Path, NXSourceFile(true, true),
            SearchPaths, LibraryPaths, ExtraOptions);
        end;
      targetCustom:
        begin
          case OS of
            Android:
              begin
                Compile(OS, CPU, Plugin, Mode, Path, AndroidSourceFile(true, true),
                  SearchPaths, LibraryPaths, ExtraOptions);
                { Our default compilation output doesn't contain CPU suffix,
                  but we need the CPU suffix to differentiate between Android/ARM and Android/Aarch64. }
                CheckRenameFile(AndroidLibraryFile(cpuNone), AndroidLibraryFile(CPU));
                Writeln('Compiled library for Android in ', AndroidLibraryFile(CPU, false));
              end;
            else
              begin
                if Plugin then
                begin
                  MainSource := PluginSourceFile(false, true);
                  if MainSource = '' then
                    raise Exception.Create('plugin_source property for project not defined, cannot compile plugin version');
                end else
                begin
                  MainSource := StandaloneSourceFile(false, true);
                  if MainSource = '' then
                    raise Exception.Create('standalone_source property for project not defined, cannot compile standalone version');
                end;

                if MakeAutoGeneratedResources(Self, Path + ExtractFilePath(MainSource), OS, CPU, Plugin) then
                  ExtraOptions.Add('-dCASTLE_AUTO_GENERATED_RESOURCES');

                Compile(OS, CPU, Plugin, Mode, Path, MainSource,
                  SearchPaths, LibraryPaths, ExtraOptions);

                if Plugin then
                begin
                  SourceExe := CompiledLibraryFile(MainSource, OS);
                  DestExe := PluginLibraryFile(OS, CPU);
                end else
                begin
                  SourceExe := ChangeFileExt(MainSource, ExeExtensionOS(OS));
                  DestExe := ChangeFileExt(ExecutableName, ExeExtensionOS(OS));
                  AddExternalLibraries(ExtractFilePath(DestExe));
                end;
                if not SameFileName(SourceExe, DestExe) then
                begin
                  { move exe to top-level (in case MainSource is in subdirectory
                    like code/) and eventually rename to follow ExecutableName }
                  Writeln('Moving ', SourceExe, ' to ', DestExe);
                  CheckRenameFile(
                    CombinePaths(Path, SourceExe),
                    CombinePaths(OutputPath, DestExe));
                end;
              end;
          end;
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('Unhandled --target for DoCompile');
      {$endif}
    end;
  finally FreeAndNil(ExtraOptions) end;
end;

function TCastleProject.PluginLibraryFile(const OS: TOS; const CPU: TCPU): string;
begin
  { "np" prefix is safest for plugin library files. }
  Result := ExtractFilePath(ExecutableName) + 'np' +
    DeleteFileExt(ExtractFileName(ExecutableName)) + '.' +
    OSToString(OS) + '-' + CPUToString(CPU) + LibraryExtensionOS(OS);
end;

function TCastleProject.PackageFiles(const OnlyData: boolean;
  const TargetPlatform: TCastlePlatform): TCastleStringList;
var
  Collector: TBinaryPackageFiles;
begin
  Result := TCastleStringList.Create;
  try
    Collector := TBinaryPackageFiles.Create(Self);
    try
      Collector.IncludePaths := Manifest.IncludePaths;
      Collector.ExcludePaths := Manifest.ExcludePaths;
      Collector.IncludePathsRecursive := Manifest.IncludePathsRecursive;
      Collector.OnlyData := OnlyData;
      Collector.TargetPlatform := TargetPlatform;
      Collector.Run;
      Result.Assign(Collector.CollectedFiles);
    finally FreeAndNil(Collector) end;
  except FreeAndNil(Result); raise; end;
end;

procedure TCastleProject.ExternalLibraries(const OS: TOS; const CPU: TCPU; const List: TStrings;
  const CheckFilesExistence: Boolean);

  { Path to the external library in data/external_libraries/ .
    Right now, these host various Windows-specific DLL files.
    If CheckFilesExistence then this checks existence of appropriate files along the way,
    and raises exception in case of trouble. }
  function ExternalLibraryPath(const OS: TOS; const CPU: TCPU; const LibraryName: string): string;
  var
    LibraryURL: string;
  begin
    LibraryURL := ApplicationData('external_libraries/' + CPUToString(CPU) + '-' + OSToString(OS) + '/' + LibraryName);
    Result := URIToFilenameSafe(LibraryURL);
    if CheckFilesExistence and (not RegularFileExists(Result)) then
      raise Exception.Create('Cannot find dependency library in "' + Result + '". ' + SErrDataDir);
  end;

  procedure AddExternalLibrary(const LibraryName: string);
  begin
    List.Add(ExternalLibraryPath(OS, CPU, LibraryName));
  end;

begin
  case OS of
    win32:
      begin
        if depFreetype in Dependencies then
          AddExternalLibrary('freetype-6.dll');
        if depZlib in Dependencies then
          AddExternalLibrary('zlib1.dll');
        if depPng in Dependencies then
          AddExternalLibrary('libpng12.dll');
        if depSound in Dependencies then
        begin
          AddExternalLibrary('OpenAL32.dll');
          AddExternalLibrary('wrap_oal.dll');
        end;
        if depOggVorbis in Dependencies then
        begin
          AddExternalLibrary('ogg.dll');
          AddExternalLibrary('vorbis.dll');
          AddExternalLibrary('vorbisenc.dll');
          AddExternalLibrary('vorbisfile.dll');
        end;
        if depHttps in Dependencies then
        begin
          AddExternalLibrary('openssl/libeay32.dll');
          AddExternalLibrary('openssl/ssleay32.dll');
        end;
      end;

    win64:
      begin
        if depFreetype in Dependencies then
          AddExternalLibrary('freetype-6.dll');
        if depZlib in Dependencies then
          AddExternalLibrary('zlib1.dll');
        if depPng in Dependencies then
          AddExternalLibrary('libpng14-14.dll');
        if depSound in Dependencies then
        begin
          AddExternalLibrary('OpenAL32.dll');
          AddExternalLibrary('wrap_oal.dll');
        end;
        if depOggVorbis in Dependencies then
        begin
          AddExternalLibrary('libogg.dll');
          AddExternalLibrary('libvorbis.dll');
          { AddExternalLibrary('vorbisenc.dll'); not present? }
          AddExternalLibrary('vorbisfile.dll');
        end;
        if depHttps in Dependencies then
        begin
          AddExternalLibrary('openssl/libeay32.dll');
          AddExternalLibrary('openssl/ssleay32.dll');
        end;
      end;
    else ; { no need to do anything on other OSes }
  end;
end;

procedure TCastleProject.DoPackage(const Target: TTarget;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Mode: TCompilationMode; const PackageFormat: TPackageFormat;
  const PackageNameIncludeVersion, UpdateOnlyCode: Boolean);
var
  Pack: TPackageDirectory;

  procedure AddExecutable;
  var
    ExecutableNameExt, ExecutableNameFull: string;
    UnixPermissionsMatter: boolean;
  begin
    if OS in [linux, go32v2, win32, os2, freebsd, beos, netbsd,
              amiga, atari, solaris, qnx, netware, openbsd, wdosx,
              palmos, macos, darwin, emx, watcom, morphos, netwlibc,
              win64, wince, gba,nds, embedded, symbian, haiku, {iphonesim,}
              aix, java, {android,} nativent, msdos, wii] then
    begin
      ExecutableNameExt := ExecutableName + ExeExtensionOS(OS);
      ExecutableNameFull := OutputPath + ExecutableNameExt;
      Pack.Add(ExecutableNameFull, ExecutableNameExt);

      { For OSes where chmod matters, make sure to set it before packing }
      UnixPermissionsMatter := not (OS in AllWindowsOSes);
      if UnixPermissionsMatter then
        Pack.MakeExecutable(ExecutableNameExt);
    end;
  end;

  procedure AddExternalLibraries;
  var
    List: TCastleStringList;
    FileName: String;
  begin
    List := TCastleStringList.Create;
    try
      ExternalLibraries(OS, CPU, List);
      for FileName in List do
        Pack.Add(FileName, ExtractFileName(FileName));
    finally FreeAndNil(List) end;
  end;

  { How the targets are detected (at build (right here) and inside the compiled application
    (in Platform implementation)) is a bit complicated.

    - nintendo-switch:

        At build: building for [[Nintendo Switch]] using CGE build tool with --target=nintendo-switch .

        Inside the application: if code was compiled with CASTLE_NINTENDO_SWITCH.

    - Android

        When OS is Android (currently possible values: Android/Arm, Android/Aarch64), and it is *not* detected as _Nintendo Switch_ (for internal reasons, right now _Nintendo Switch_ is also treated as Android by FPC).

        This logic is used both at build, and inside the application.

    - iOS: When OS is iPhoneSim or OS/architecture are Darwin/Arm or Darwin/Aarch64.

        In total this has 4 currently possible values: iPhoneSim/i386, iPhoneSim/x86_64, Darwin/Arm, Darwin/Aarch64.

        This logic is used both at build, and inside the application.

    - desktop: everything else.
  }
  function TargetPlatform: TCastlePlatform;
  begin
    case Target of
      targetIOS: Result := cpIOS;
      targetAndroid: Result := cpAndroid;
      targetNintendoSwitch: Result := cpNintendoSwitch;
      else // only targetCustom for now
      begin
        if OS = Android then
          Result := cpAndroid
        else
        if (OS = iphonesim) or
           ((OS = darwin) and (CPU = arm)) or
           ((OS = darwin) and (CPU = aarch64)) then
          Result := cpIOS
        else
          Result := cpDesktop;
      end;
    end;
  end;

var
  I: Integer;
  PackageFileName: string;
  Files: TCastleStringList;
  PackageFormatFinal: TPackageFormatNoDefault;
  WantsIOSArchive: Boolean;
  IOSArchiveType: TIosArchiveType;
begin
  Writeln(Format('Packaging project "%s" for %s (platform: %s).', [
    Name,
    TargetCompleteToString(Target, OS, CPU, Plugin),
    PlatformToStr(TargetPlatform)
  ]));

  if Plugin then
    raise Exception.Create('The "package" command is not useful to package plugins for now');

  { for iOS, the packaging process is special }
  if (Target = targetIOS) and
     (PackageFormat in [pfDefault, pfIosArchiveDevelopment, pfIosArchiveAdHoc, pfIosArchiveAppStore]) then
  begin
    // set IOSExportMethod early, as it determines IOS_EXPORT_METHOD macro
    WantsIOSArchive := PackageFormatWantsIOSArchive(PackageFormat, IOSArchiveType, IOSExportMethod);
    PackageIOS(Self, UpdateOnlyCode);
    if WantsIOSArchive then
      ArchiveIOS(Self, IOSArchiveType);
    Exit;
  end;

  if PackageFormat = pfDefault then
  begin
    { for Android, the packaging process is special }
    if (Target = targetAndroid) or (OS = Android) then
    begin
      if Target = targetAndroid then
        AndroidCPUS := DetectAndroidCPUS
      else
        AndroidCPUS := [CPU];
      PackageAndroid(Self, OS, AndroidCPUS, Mode);
      Exit;
    end;

    { for Nintendo Switch, the packaging process is special }
    if Target = targetNintendoSwitch then
    begin
      PackageNintendoSwitch(Self);
      Exit;
    end;

    { calculate PackageFormatFinal }
    if OS in AllWindowsOSes then
      PackageFormatFinal := pfZip
    else
      PackageFormatFinal := pfTarGz;
  end else
    PackageFormatFinal := PackageFormat;

  Pack := TPackageDirectory.Create(Name);
  try
    { executable is added 1st, since it's the most likely file
      to not exist, so we'll fail earlier }
    AddExecutable;
    AddExternalLibraries;

    Files := PackageFiles(false, TargetPlatform);
    try
      for I := 0 to Files.Count - 1 do
        Pack.Add(Path + Files[I], Files[I]);
    finally FreeAndNil(Files) end;

    Pack.AddDataInformation(TCastleManifest.DataName);

    PackageFileName := PackageName(OS, CPU, PackageFormatFinal, PackageNameIncludeVersion);
    Pack.Make(OutputPath, PackageFileName, PackageFormatFinal);
  finally FreeAndNil(Pack) end;
end;

procedure TCastleProject.DoInstall(const Target: TTarget;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean);

  {$ifdef UNIX}
  procedure InstallUnixPlugin;
  const
    TargetPathSystemWide = '/usr/lib/mozilla/plugins/';
  var
    PluginFile, Source, Target: string;
  begin
    PluginFile := PluginLibraryFile(OS, CPU);
    Source := InclPathDelim(OutputPath) + PluginFile;
    Target := TargetPathSystemWide + PluginFile;
    try
      SmartCopyFile(Source, Target);
      Writeln('Installed system-wide by copying the plugin to "' + Target + '".');
    except
      on E: Exception do
      begin
        Writeln('Failed to install system-wide (' + E.ClassName + ': ' + E.Message + ').');
        Target := HomePath + '.mozilla/plugins/' + PluginFile;
        SmartCopyFile(Source, Target);
        Writeln('Installed to "' + Target + '".');
      end;
    end;
  end;
  {$endif}

begin
  Writeln(Format('Installing project "%s" for %s.',
    [Name, TargetCompleteToString(Target, OS, CPU, Plugin)]));

  if Target = targetIOS then
    InstallIOS(Self)
  else
  if (Target = targetAndroid) or (OS = Android) then
    InstallAndroid(Name, QualifiedName, OutputPath)
  else
  if Plugin and (OS in AllWindowsOSes) then
    InstallWindowsPluginRegistry(Name, QualifiedName, OutputPath,
      PluginLibraryFile(OS, CPU), Version.DisplayValue, Author)
  else
  {$ifdef UNIX}
  if Plugin and (OS in AllUnixOSes) then
    InstallUnixPlugin
  else
  {$endif}
    raise Exception.Create('The "install" command is not useful for this target / OS / CPU right now. Install the application manually.');
end;

procedure TCastleProject.DoRun(const Target: TTarget;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Params: TCastleStringList);

  procedure MaybeUseWrapperToRun(var ExeName: String);
  var
    S: String;
  begin
    if OS in AllUnixOSes then
    begin
      S := Path + ChangeFileExt(ExecutableName, '') + '_run.sh';
      if RegularFileExists(S) then
      begin
        ExeName := S;
        Exit;
      end;

      S := Path + 'run.sh';
      if RegularFileExists(S) then
      begin
        ExeName := S;
        Exit;
      end;
    end;
  end;

var
  ExeName: string;
begin
  Writeln(Format('Running project "%s" for %s.',
    [Name, TargetCompleteToString(Target, OS, CPU, Plugin)]));

  if Plugin then
    raise Exception.Create('The "run" command cannot be used for runninig "plugin" type application right now.');

  if Target = targetIOS then
    RunIOS(Self)
  else
  if (Target = targetAndroid) or (OS = Android) then
    RunAndroid(Self)
  else
  if Target = targetCustom then
  begin
    ExeName := Path + ChangeFileExt(ExecutableName, ExeExtensionOS(OS));
    MaybeUseWrapperToRun(ExeName);
    Writeln('Running ' + ExeName);
    { We set current path to Path, not OutputPath, because data/ subdirectory is under Path. }
    RunCommandSimple(Path, ExeName, Params.ToArray, 'CASTLE_LOG', 'stdout');
  end else
    raise Exception.Create('The "run" command is not useful for this OS / CPU right now. Run the application manually.');
end;

procedure TCastleProject.DoPackageSource(const PackageFormat: TPackageFormat;
  const PackageNameIncludeVersion: Boolean);
var
  PackageFormatFinal: TPackageFormatNoDefault;
  Pack: TPackageDirectory;
  Files: TCastleStringList;
  I: Integer;
  PackageFileName: string;
  Collector: TSourcePackageFiles;
begin
  Writeln(Format('Packaging source code of project "%s".', [Name]));

  if PackageFormat = pfDefault then
    PackageFormatFinal := pfZip
  else
    PackageFormatFinal := PackageFormat;

  Pack := TPackageDirectory.Create(Name);
  try
    Files := TCastleStringList.Create;
    try
      Collector := TSourcePackageFiles.Create(Self);
      try
        Collector.Run;
        Files.Assign(Collector.CollectedFiles);
      finally FreeAndNil(Collector) end;

      for I := 0 to Files.Count - 1 do
        Pack.Add(Path + Files[I], Files[I]);
    finally FreeAndNil(Files) end;

    PackageFileName := SourcePackageName(PackageNameIncludeVersion);
    Pack.Make(OutputPath, PackageFileName, PackageFormatFinal);
  finally FreeAndNil(Pack) end;
end;

function TCastleProject.PackageName(const OS: TOS; const CPU: TCPU;
  const PackageFormat: TPackageFormatNoDefault;
  const PackageNameIncludeVersion: Boolean): string;
begin
  Result := Name;
  if PackageNameIncludeVersion and (Version.DisplayValue <> '') then
    Result += '-' + Version.DisplayValue;
  Result += '-' + OSToString(OS) + '-' + CPUToString(CPU);
  case PackageFormat of
    pfZip: Result += '.zip';
    pfTarGz: Result += '.tar.gz';
    else ; // leave without extension for pfDirectory
  end;
end;

function TCastleProject.SourcePackageName(const PackageNameIncludeVersion: Boolean): string;
begin
  Result := Name;
  if PackageNameIncludeVersion and (Version.DisplayValue <> '') then
    Result += '-' + Version.DisplayValue;
  Result += '-src';
  Result += '.tar.gz';
end;

procedure TCastleProject.DeleteFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);
begin
  if Verbose then
    Writeln('Deleting ' + FileInfo.AbsoluteName);
  CheckDeleteFile(FileInfo.AbsoluteName);
  Inc(DeletedFiles);
end;

function TCastleProject.NamePascal: string;
begin
  Result := MakeProjectPascalName(Name);
end;

procedure TCastleProject.GeneratedSourceFile(
  const TemplateRelativeURL, TargetRelativePath, ErrorMessageMissingGameUnits: string;
  const CreateIfNecessary: boolean;
  out RelativeResult, AbsoluteResult: string);
var
  TemplateFile: string;
begin
  AbsoluteResult := TempOutputPath(Path, CreateIfNecessary) + TargetRelativePath;
  if CreateIfNecessary then
  begin
    TemplateFile := URIToFilenameSafe(ApplicationData(TemplateRelativeURL));
    if Manifest.GameUnits = '' then
      raise Exception.Create(ErrorMessageMissingGameUnits);
    ExtractTemplateFile(TemplateFile, AbsoluteResult, TemplateRelativeURL, true);
  end;
  // This may not be true anymore, if user changes OutputPathBase
  // if not IsPrefix(Path, AbsoluteResult, true) then
  //   raise EInternalError.CreateFmt('Something is wrong with the temporary source location "%s", it is not within the project "%s"',
  //     [AbsoluteResult, Path]);
  RelativeResult := PrefixRemove(Path, AbsoluteResult, true);
end;

procedure TCastleProject.GeneratedSourceFile(
  const TemplateRelativeURL, TargetRelativePath, ErrorMessageMissingGameUnits: string;
  const CreateIfNecessary: boolean);
var
  RelativeResult, AbsoluteResult: string;
begin
  GeneratedSourceFile(TemplateRelativeURL, TargetRelativePath, ErrorMessageMissingGameUnits,
    CreateIfNecessary, RelativeResult, AbsoluteResult);
  // just ignore RelativeResult, AbsoluteResult output values
end;

function TCastleProject.AndroidSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;

  procedure InvalidAndroidSource(const FinalAndroidSource: string);
  begin
    raise Exception.Create('The android source library in "' + FinalAndroidSource + '" must export the necessary JNI functions for our integration to work. See the examples in "castle-engine/tools/build-tool/data/android/library_template_xxx.lpr".' + NL + 'It''s simplest to fix this error by removing the "android_source" from CastleEngineManifest.xml, and using only the "game_units" attribute in CastleEngineManifest.xml. Then the correct Android code will be auto-generated for you.');
  end;

const
  ErrorMessageMissingGameUnits = 'You must specify game_units="..." in the CastleEngineManifest.xml to enable build tool to create an Android project. Alternatively, you can specify android_source="..." in the CastleEngineManifest.xml, to explicitly indicate the Android library source code.';
var
  AndroidSourceContents, RelativeResult, AbsoluteResult, TemplateRelativeURL: string;
begin
  { calculate RelativeResult, AbsoluteResult }
  if Manifest.AndroidSource <> '' then
  begin
    RelativeResult := Manifest.AndroidSource;
    AbsoluteResult := Path + RelativeResult;
  end else
  begin
    if AndroidProjectType = apIntegrated then
      TemplateRelativeURL := 'android/library_template_integrated.lpr'
    else
      TemplateRelativeURL := 'android/library_template_base.lpr';
    GeneratedSourceFile(TemplateRelativeURL,
      'android' + PathDelim + NamePascal + '_android.lpr',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary, RelativeResult, AbsoluteResult);
    GeneratedSourceFile('castleautogenerated_template.pas',
      'android/castleautogenerated.pas',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary);
  end;

  // for speed, do not check correctness if CreateIfNecessary = false
  if CreateIfNecessary then
  begin
    { check Android lpr file correctness.
      For now, do it even if we generated Android project from our own template
      (when AndroidSource = ''), to check our own work. }
    AndroidSourceContents := FileToString(AbsoluteResult);
    if Pos('ANativeActivity_onCreate', AndroidSourceContents) = 0 then
      InvalidAndroidSource(AbsoluteResult);
    if (AndroidProjectType = apIntegrated) and
       (Pos('Java_net_sourceforge_castleengine_MainActivity_jniMessage', AndroidSourceContents) = 0) then
      InvalidAndroidSource(AbsoluteResult);
  end;

  if AbsolutePath then
    Result := AbsoluteResult
  else
    Result := RelativeResult;
end;

function TCastleProject.IOSSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
const
  ErrorMessageMissingGameUnits = 'You must specify game_units="..." in the CastleEngineManifest.xml to enable build tool to create an iOS project. Alternatively, you can specify ios_source="..." in the CastleEngineManifest.xml, to explicitly indicate the iOS library source code.';
var
  RelativeResult, AbsoluteResult: string;
begin
  if Manifest.IOSSource <> '' then
  begin
    RelativeResult := Manifest.IOSSource;
    AbsoluteResult := Path + RelativeResult;
  end else
  begin
    GeneratedSourceFile('ios/library_template.lpr',
      'ios' + PathDelim + NamePascal + '_ios.lpr',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary, RelativeResult, AbsoluteResult);
    GeneratedSourceFile('castleautogenerated_template.pas',
      'android/castleautogenerated.pas',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary);
  end;

  if AbsolutePath then
    Result := AbsoluteResult
  else
    Result := RelativeResult;
end;

function TCastleProject.NXSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
const
  ErrorMessageMissingGameUnits = 'You must specify game_units="..." in the CastleEngineManifest.xml to enable build tool to create a Nintendo Switch project.';
var
  RelativeResult, AbsoluteResult: string;
begin
  { Without this, we would also have an error, but NxNotSupported makes
    nicer error message. }
  NxNotSupported;

  GeneratedSourceFile('nintendo_switch/library_template.lpr',
    'nintendo_switch' + PathDelim + 'castle_nx.lpr',
    ErrorMessageMissingGameUnits,
    CreateIfNecessary, RelativeResult, AbsoluteResult);
  GeneratedSourceFile('castleautogenerated_template.pas',
    'android/castleautogenerated.pas',
    ErrorMessageMissingGameUnits,
    CreateIfNecessary);

  if AbsolutePath then
    Result := AbsoluteResult
  else
    Result := RelativeResult;
end;

function TCastleProject.StandaloneSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
const
  ErrorMessageMissingGameUnits = 'You must specify game_units or standalone_source in the CastleEngineManifest.xml to compile for the standalone platform';
var
  RelativeResult, AbsoluteResult: string;
begin
  if Manifest.StandaloneSource <> '' then
  begin
    RelativeResult := Manifest.StandaloneSource;
    AbsoluteResult := Path + RelativeResult;
  end else
  begin
    GeneratedSourceFile('standalone/program_template.lpr',
      'standalone' + PathDelim + NamePascal + '_standalone.lpr',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary, RelativeResult, AbsoluteResult);
    GeneratedSourceFile('castleautogenerated_template.pas',
      'android/castleautogenerated.pas',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary);
  end;

  if AbsolutePath then
    Result := AbsoluteResult
  else
    Result := RelativeResult;
end;

function TCastleProject.PluginSourceFile(const AbsolutePath, CreateIfNecessary: boolean): string;
const
  ErrorMessageMissingGameUnits = 'You must specify game_units or plugin_source in the CastleEngineManifest.xml to compile a plugin';
var
  RelativeResult, AbsoluteResult: string;
begin
  if Manifest.PluginSource <> '' then
  begin
    RelativeResult := Manifest.PluginSource;
    AbsoluteResult := Path + RelativeResult;
  end else
  begin
    GeneratedSourceFile('plugin/library_template.lpr',
      'plugin' + PathDelim + NamePascal + '_plugin.lpr',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary, RelativeResult, AbsoluteResult);
    GeneratedSourceFile('castleautogenerated_template.pas',
      'android/castleautogenerated.pas',
      ErrorMessageMissingGameUnits,
      CreateIfNecessary);
  end;

  if AbsolutePath then
    Result := AbsoluteResult
  else
    Result := RelativeResult;
end;

function TCastleProject.AndroidLibraryFile(const CPU: TCPU;
  const AbsolutePath: boolean): string;
var
  Ext: String;
begin
  Ext := '.so';
  if CPU <> cpuNone then
    Ext := '_' + CPUToString(CPU) + Ext;
  Result := InsertLibPrefix(ChangeFileExt(AndroidSourceFile(AbsolutePath, false), Ext));
end;

function TCastleProject.IOSLibraryFile(const AbsolutePath: boolean): string;
begin
  Result := InsertLibPrefix(ChangeFileExt(IOSSourceFile(AbsolutePath, false), '.a'));
end;

function TCastleProject.NXLibraryFile(const AbsolutePath: boolean): string;
begin
  Result := InsertLibPrefix(ChangeFileExt(NXSourceFile(AbsolutePath, false), '.a'));
end;

procedure TCastleProject.DoClean;

  { Delete a file, given as absolute FileName. }
  procedure TryDeleteAbsoluteFile(FileName: string);
  begin
    if RegularFileExists(FileName) then
    begin
      if Verbose then
        Writeln('Deleting ' + FileName);
      CheckDeleteFile(FileName);
      Inc(DeletedFiles);
    end;
  end;

  { Delete a file, given as FileName relative to project root. }
  procedure TryDeleteFile(FileName: string);
  begin
    TryDeleteAbsoluteFile(Path + FileName);
  end;

  procedure DeleteFilesRecursive(const Mask: string);
  begin
    FindFiles(Path, Mask, false, @DeleteFoundFile, [ffRecursive]);
  end;

  procedure DeleteExternalLibraries(const LibrariesOutputPath: String; const OS: TOS; const CPU: TCPU);
  var
    List: TCastleStringList;
    OutputFile, FileName: String;
  begin
    List := TCastleStringList.Create;
    try
      { CheckFilesExistence parameter for ExternalLibraries may be false.
        This way you can run "castle-engine clean" without setting $CASTLE_ENGINE_PATH . }
      ExternalLibraries(OS, CPU, List, false);
      for FileName in List do
      begin
        OutputFile := LibrariesOutputPath + ExtractFileName(FileName);
        TryDeleteFile(OutputFile);
      end;
    finally FreeAndNil(List) end;
  end;

var
  OS: TOS;
  CPU: TCPU;
  OutputP: string;
begin
  { delete OutputPath first, this also removes many files
    (but RemoveNonEmptyDir does not count them) }
  OutputP := TempOutputPath(Path, false);
  if DirectoryExists(OutputP) then
  begin
    RemoveNonEmptyDir(OutputP);
    Writeln('Deleted ', OutputP);
  end;

  DeletedFiles := 0;

  TryDeleteFile(ChangeFileExt(ExecutableName, ''));
  TryDeleteFile(ChangeFileExt(ExecutableName, '.exe'));
  TryDeleteFile(ChangeFileExt(ExecutableName, '.log'));

  if Manifest.AndroidSource <> '' then
  begin
    TryDeleteAbsoluteFile(AndroidLibraryFile(arm));
    TryDeleteAbsoluteFile(AndroidLibraryFile(aarch64));
  end;
  if Manifest.IOSSource <> '' then
    TryDeleteAbsoluteFile(IOSLibraryFile);

  for OS in TOS do
    for CPU in TCPU do
      if OSCPUSupported[OS, CPU] then
      begin
        { possible plugin outputs }
        if Manifest.PluginSource <> '' then
          TryDeleteFile(PluginLibraryFile(OS, CPU));

        { packages created by DoPackage? Or not, it's safer to not remove them. }
        // TryDeleteFile(PackageName(OS, CPU));

        DeleteExternalLibraries(ExtractFilePath(ExecutableName), OS, CPU);
      end;

  { compilation and editor backups }
  DeleteFilesRecursive('*~'); // editor backup, e.g. Emacs
  DeleteFilesRecursive('*.ppu'); // compilation
  DeleteFilesRecursive('*.o'); // compilation
  DeleteFilesRecursive('*.or'); // compilation
  DeleteFilesRecursive('*.compiled'); // Lazarus compilation
  DeleteFilesRecursive('*.rst'); // resource strings
  DeleteFilesRecursive('*.rsj'); // resource strings
  TryDeleteFile('castle-auto-generated-resources.res');
  TryDeleteFile('castle-plugin-auto-generated-resources.res');

  Writeln('Deleted ', DeletedFiles, ' files');
end;

procedure TCastleProject.DoAutoGenerateTextures;
begin
  AutoGenerateTextures(Self);
end;

procedure TCastleProject.DoAutoGenerateClean(const CleanAll: Boolean);
begin
  if CleanAll then
    AutoGenerateCleanAll(Self)
  else
    AutoGenerateCleanUnused(Self);
end;

procedure TCastleProject.DoGenerateProgram;

  procedure Generate(const TemplateRelativePath, TargeRelativePath: string);
  var
    TemplateFile, TargetFile: string;
  begin
    TemplateFile := URIToFilenameSafe(ApplicationData(TemplateRelativePath));
    TargetFile := Path + TargeRelativePath;
    ExtractTemplateFile(TemplateFile, TargetFile, TemplateRelativePath, true);
    Writeln('Generated ', ExtractRelativePath(Path, TargetFile));
  end;

  procedure GenerateStandaloneProgram(const Ext: string);
  begin
    Generate(
      'standalone/program_template.' + Ext,
      NamePascal + '_standalone.' + Ext);
  end;

begin
  if Manifest.GameUnits = '' then
    raise Exception.Create('You must specify game_units="..." in the CastleEngineManifest.xml to enable build tool to create a standalone project');
  GenerateStandaloneProgram('lpr');
  GenerateStandaloneProgram('lpi');
  Generate('castleautogenerated_template.pas', 'castleautogenerated.pas');
end;

procedure TCastleProject.DoEditor;
var
  EditorExe, CgePath, EditorPath, LazbuildExe: String;
begin
  if Trim(Manifest.EditorUnits) = '' then
  begin
    EditorExe := FindExeCastleTool('castle-editor');
    if EditorExe = '' then
      raise Exception.Create('Cannot find "castle-editor" program on $PATH or within $CASTLE_ENGINE_PATH/bin directory.');
  end else
  begin
    { Check CastleEnginePath, since without this, compiling custom castle-editor.lpi
      will always fail. }
    CgePath := CastleEnginePath;
    if CgePath = '' then
      raise Exception.Create('Cannot find Castle Game Engine sources. Make sure that the environment variable CASTLE_ENGINE_PATH is correctly defined.');

    // create custom editor directory
    EditorPath := TempOutputPath(Path) + 'editor' + PathDelim;
    { Do not remove previous directory contents,
      allows to reuse previous lazbuild compilation results.
      Just silence ExtractTemplate warnings when overriding. }
    ExtractTemplate('custom_editor_template/', EditorPath, true);

    // use lazbuild to compile CGE packages and CGE editor
    LazbuildExe := FindExeLazarus('lazbuild');
    if LazbuildExe = '' then
      raise Exception.Create('Cannot find "lazbuild" program on $PATH. It is needed to build a custom CGE editor version.');
    RunCommandSimple(LazbuildExe, CgePath + 'packages' + PathDelim + 'castle_base.lpk');
    RunCommandSimple(LazbuildExe, CgePath + 'packages' + PathDelim + 'castle_components.lpk');
    RunCommandSimple(LazbuildExe, EditorPath + 'castle_editor_automatic_package.lpk');
    RunCommandSimple(LazbuildExe, EditorPath + 'castle_editor.lpi');

    EditorExe := EditorPath + 'castle-editor' + ExeExtension;
    if not RegularFileExists(EditorExe) then
      raise Exception.Create('Editor should be compiled, but (for an unknown reason) we cannot find file "' + EditorExe + '"');
  end;

  RunCommandNoWait(TempOutputPath(Path), EditorExe, [ManifestFile]);
end;

procedure TCastleProject.AddMacrosAndroid(const Macros: TStringStringMap);
const
  AndroidScreenOrientation: array [TScreenOrientation] of string =
  ('unspecified', 'sensorLandscape', 'sensorPortrait');

  AndroidScreenOrientationFeature: array [TScreenOrientation] of string =
  ('',
   '<uses-feature android:name="android.hardware.screen.landscape"/>',
   '<uses-feature android:name="android.hardware.screen.portrait"/>');

  function AndroidActivityTheme: string;
  begin
    if FullscreenImmersive then
      Result := 'android:Theme.NoTitleBar.Fullscreen'
    else
      Result := 'android:Theme.NoTitleBar';
  end;

  function AndroidActivityLoadLibraries: string;
  begin
    { some Android devices work without this clause, some don't }
    Result := '';
    if depSound in Dependencies then
      Result += 'safeLoadLibrary("openal");' + NL;
    if depOggVorbis in Dependencies then
      Result += 'safeLoadLibrary("tremolo");' + NL;
    if depFreetype in Dependencies then
      Result += 'safeLoadLibrary("freetype");' + NL;
  end;

  { Android ABI list like '"armeabi-v7a","arm64-v8a"' }
  function AndroidAbiList: String;
  var
    CPU: TCPU;
  begin
    Result := '';
    for CPU in AndroidCPUS do
      Result := SAppendPart(Result, ',', '"' + CPUToAndroidArchitecture(CPU) + '"');
  end;

  { Android ABI list like 'armeabi-v7a arm64-v8a' }
  function AndroidAbiListMakefile: String;
  var
    CPU: TCPU;
  begin
    Result := '';
    for CPU in AndroidCPUS do
      Result := SAppendPart(Result, ' ', CPUToAndroidArchitecture(CPU));
  end;

var
  AndroidLibraryName: string;
  Service: TService;
begin
  AndroidLibraryName := ChangeFileExt(ExtractFileName(AndroidSourceFile(true, false)), '');
  Macros.Add('ANDROID_LIBRARY_NAME'                , AndroidLibraryName);
  Macros.Add('ANDROID_ACTIVITY_THEME'              , AndroidActivityTheme);
  Macros.Add('ANDROID_SCREEN_ORIENTATION'          , AndroidScreenOrientation[ScreenOrientation]);
  Macros.Add('ANDROID_SCREEN_ORIENTATION_FEATURE'  , AndroidScreenOrientationFeature[ScreenOrientation]);
  Macros.Add('ANDROID_ACTIVITY_LOAD_LIBRARIES'     , AndroidActivityLoadLibraries);
  Macros.Add('ANDROID_COMPILE_SDK_VERSION'         , IntToStr(AndroidCompileSdkVersion));
  Macros.Add('ANDROID_MIN_SDK_VERSION'             , IntToStr(AndroidMinSdkVersion));
  Macros.Add('ANDROID_TARGET_SDK_VERSION'          , IntToStr(AndroidTargetSdkVersion));
  Macros.Add('ANDROID_ASSOCIATE_DOCUMENT_TYPES'    , AssociateDocumentTypes.ToIntentFilter);
  Macros.Add('ANDROID_LOG_TAG'                     , Copy(Name, 1, MaxAndroidTagLength));
  Macros.Add('ANDROID_ABI_LIST'                    , AndroidAbiList);
  Macros.Add('ANDROID_ABI_LIST_MAKEFILE'           , AndroidAbiListMakefile);

  for Service in AndroidServices do
    ParametersAddMacros(Macros, Service.Parameters, 'ANDROID.' + Service.Name + '.');
end;

procedure TCastleProject.AddMacrosIOS(const Macros: TStringStringMap);
const
  IOSScreenOrientation: array [TScreenOrientation] of string =
  (#9#9'<string>UIInterfaceOrientationPortrait</string>' + NL +
   #9#9'<string>UIInterfaceOrientationPortraitUpsideDown</string>' + NL +
   #9#9'<string>UIInterfaceOrientationLandscapeLeft</string>' + NL +
   #9#9'<string>UIInterfaceOrientationLandscapeRight</string>' + NL,

   #9#9'<string>UIInterfaceOrientationLandscapeLeft</string>' + NL +
   #9#9'<string>UIInterfaceOrientationLandscapeRight</string>' + NL,

   #9#9'<string>UIInterfaceOrientationPortrait</string>' + NL +
   #9#9'<string>UIInterfaceOrientationPortraitUpsideDown</string>' + NL
  );

  IOSCapabilityEnable =
    #9#9#9#9#9#9#9'com.apple.%s = {' + NL +
    #9#9#9#9#9#9#9#9'enabled = 1;' + NL +
    #9#9#9#9#9#9#9'};' + NL;

  { QualifiedName for iOS: either qualified_name, or ios.override_qualified_name. }
  function IOSQualifiedName: string;
  begin
    if Manifest.IOSOverrideQualifiedName <> '' then
      Result := Manifest.IOSOverrideQualifiedName
    else
      Result := QualifiedName;
  end;

var
  P, IOSTargetAttributes, IOSRequiredDeviceCapabilities, IOSSystemCapabilities: string;
  Service: TService;
  IOSVersion: TProjectVersion;
  GccPreprocessorDefinitions: String;
begin
  if Manifest.IOSOverrideVersion <> nil then
    IOSVersion := Manifest.IOSOverrideVersion
  else
    IOSVersion := Manifest.Version;
  Macros.Add('IOS_QUALIFIED_NAME', IOSQualifiedName);
  Macros.Add('IOS_VERSION', IOSVersion.DisplayValue);
  Macros.Add('IOS_VERSION_CODE', IntToStr(IOSVersion.Code));
  Macros.Add('IOS_LIBRARY_BASE_NAME' , ExtractFileName(IOSLibraryFile));
  Macros.Add('IOS_STATUSBAR_HIDDEN', BoolToStr(FullscreenImmersive, 'YES', 'NO'));
  Macros.Add('IOS_SCREEN_ORIENTATION', IOSScreenOrientation[ScreenOrientation]);
  P := AssociateDocumentTypes.ToPListSection(IOSQualifiedName, 'AppIcon');
  if not Manifest.UsesNonExemptEncryption then
    P := SAppendPart(P, NL, '<key>ITSAppUsesNonExemptEncryption</key> <false/>');
  Macros.Add('IOS_EXTRA_INFO_PLIST', P);

  IOSTargetAttributes := '';
  IOSRequiredDeviceCapabilities := '';
  if Manifest.IOSTeam <> '' then
  begin
    IOSTargetAttributes := IOSTargetAttributes +
      #9#9#9#9#9#9'DevelopmentTeam = ' + Manifest.IOSTeam + ';' + NL;
    Macros.Add('IOS_DEVELOPMENT_TEAM_LINE', 'DEVELOPMENT_TEAM = ' + Manifest.IOSTeam + ';');
  end else
  begin
    Macros.Add('IOS_DEVELOPMENT_TEAM_LINE', '');
  end;

  IOSSystemCapabilities := '';
  if IOSServices.HasService('apple_game_center') then
  begin
    IOSSystemCapabilities := IOSSystemCapabilities +
      Format(IOSCapabilityEnable, ['GameCenter']);
    IOSRequiredDeviceCapabilities := IOSRequiredDeviceCapabilities +
      #9#9'<string>gamekit</string>' + NL;
  end;
  if IOSServices.HasService('icloud_for_save_games') then
    IOSSystemCapabilities := IOSSystemCapabilities +
      Format(IOSCapabilityEnable, ['iCloud']);
  if IOSServices.HasService('in_app_purchases') then
    IOSSystemCapabilities := IOSSystemCapabilities +
      Format(IOSCapabilityEnable, ['InAppPurchase']);
  // If not empty, add IOSSystemCapabilities to IOSTargetAttributes,
  // wrapped in SystemCapabilities = { } block.
  if IOSSystemCapabilities <> '' then
      IOSTargetAttributes := IOSTargetAttributes +
        #9#9#9#9#9#9'SystemCapabilities = {' + NL +
        IOSSystemCapabilities +
        #9#9#9#9#9#9'};' + NL;

  Macros.Add('IOS_TARGET_ATTRIBUTES', IOSTargetAttributes);
  Macros.Add('IOS_REQUIRED_DEVICE_CAPABILITIES', IOSRequiredDeviceCapabilities);
  Macros.Add('IOS_EXPORT_METHOD', IOSExportMethod);

  if IOSServices.HasService('icloud_for_save_games') then
    Macros.Add('IOS_CODE_SIGN_ENTITLEMENTS', 'CODE_SIGN_ENTITLEMENTS = "' + Name + '/icloud_for_save_games.entitlements";')
  else
    Macros.Add('IOS_CODE_SIGN_ENTITLEMENTS', '');

  GccPreprocessorDefinitions := '';
  // Since right now we always compile with CASTLE_TREMOLO_STATIC,
  // we just always behave like ogg_vorbis service was included.
  //if depOggVorbis in Dependencies then
    GccPreprocessorDefinitions := GccPreprocessorDefinitions + '"ONLY_C=1",' + NL;
  Macros.Add('IOS_GCC_PREPROCESSOR_DEFINITIONS', GccPreprocessorDefinitions);

  for Service in IOSServices do
    ParametersAddMacros(Macros, Service.Parameters, 'IOS.' + Service.Name + '.');
end;

function TCastleProject.ReplaceMacros(const Source: string): string;

  function MakePathsStr(const Paths: TStringList; const Absolute: Boolean): String;
  var
    S, Dir: string;
  begin
    Result := '';
    for S in Paths do
    begin
      if Result <> '' then
        Result := Result + ';';
      if Absolute then
        Dir := CombinePaths(Path, S)
      else
        Dir := S;
      Result := Result + Dir;
    end;

    { For ABSOLUTE_xxx macros, add Path (project directory).
      It is not necessary for relative paths, as their handling always includes current dir for now.
      Testcase: examples/advanced_editor/CastleEngineManifest.xml ,
      without this the "castle-engine editor" would not find GameControls. }
    if Absolute then
      Result := SAppendPart(Result, ';', Path);
  end;

var
  I: Integer;
  NonEmptyAuthor: string;
  VersionComponents: array [0..3] of Cardinal;
  VersionComponentsString: TCastleStringList;
  Macros: TStringStringMap;
begin
  { calculate version as 4 numbers, Windows resource/manifest stuff expect this }
  VersionComponentsString := CastleStringUtils.SplitString(Version.DisplayValue, '.');
  try
    for I := 0 to High(VersionComponents) do
      if I < VersionComponentsString.Count then
        VersionComponents[I] := StrToIntDef(Trim(VersionComponentsString[I]), 0) else
        VersionComponents[I] := 0;
  finally FreeAndNil(VersionComponentsString) end;

  if Author = '' then
    NonEmptyAuthor := 'Unknown Author'
  else
    NonEmptyAuthor := Author;

  Macros := TStringStringMap.Create;
  try
    Macros.Add('DOLLAR'          , '$');
    Macros.Add('VERSION_MAJOR'   , IntToStr(VersionComponents[0]));
    Macros.Add('VERSION_MINOR'   , IntToStr(VersionComponents[1]));
    Macros.Add('VERSION_RELEASE' , IntToStr(VersionComponents[2]));
    Macros.Add('VERSION_BUILD'   , IntToStr(VersionComponents[3]));
    Macros.Add('VERSION'         , Manifest.Version.DisplayValue);
    Macros.Add('VERSION_CODE'    , IntToStr(Manifest.Version.Code));
    Macros.Add('NAME'            , Name);
    Macros.Add('NAME_PASCAL'     , NamePascal);
    Macros.Add('QUALIFIED_NAME'  , QualifiedName);
    Macros.Add('CAPTION'         , Caption);
    Macros.Add('AUTHOR'          , NonEmptyAuthor);
    Macros.Add('EXECUTABLE_NAME' , ExecutableName);
    Macros.Add('GAME_UNITS'      , Manifest.GameUnits);
    Macros.Add('SEARCH_PATHS'          , MakePathsStr(SearchPaths, false));
    Macros.Add('ABSOLUTE_SEARCH_PATHS' , MakePathsStr(SearchPaths, true));
    Macros.Add('LIBRARY_PATHS'          , MakePathsStr(LibraryPaths, false));
    { Using this is important in ../data/custom_editor_template/castle_editor.lpi ,
      otherwise with FPC 3.3.1 (rev 40292) doing "castle-engine editor"
      fails when the project uses some libraries (like mORMot's .o files in static/). }
    Macros.Add('ABSOLUTE_LIBRARY_PATHS' , MakePathsStr(LibraryPaths, true));
    Macros.Add('CASTLE_ENGINE_PATH'    , CastleEnginePath);
    Macros.Add('EXTRA_COMPILER_OPTIONS', Manifest.ExtraCompilerOptions.Text);
    Macros.Add('EXTRA_COMPILER_OPTIONS_ABSOLUTE', Manifest.ExtraCompilerOptionsAbsolute.Text);
    Macros.Add('EDITOR_UNITS'          , Manifest.EditorUnits);

    AddMacrosAndroid(Macros);
    AddMacrosIOS(Macros);

    Result := ToolMacros.ReplaceMacros(Macros, Source);
  finally FreeAndNil(Macros) end;
end;

procedure TCastleProject.ExtractTemplate(const TemplatePath, DestinationPath: string;
  const OverrideExisting: boolean);
var
  TemplateFilesCount: Cardinal;
begin
  ExtractTemplateOverrideExisting := OverrideExisting;
  ExtractTemplateDestinationPath := InclPathDelim(DestinationPath);
  ExtractTemplateDir := ExclPathDelim(URIToFilenameSafe(ApplicationData(TemplatePath)));
  if not DirectoryExists(ExtractTemplateDir) then
    raise Exception.Create('Cannot find template in "' + ExtractTemplateDir + '". ' + SErrDataDir);

  TemplateFilesCount := FindFiles(ExtractTemplateDir, '*', false,
    @ExtractTemplateFoundFile, [ffRecursive]);
  if Verbose then
    Writeln(Format('Copied template "%s" (%d files) to "%s"',
      [TemplatePath, TemplateFilesCount, DestinationPath]));
end;

procedure TCastleProject.ExtractTemplateFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);
var
  DestinationRelativeFileName, DestinationFileName: string;
begin
  DestinationRelativeFileName := PrefixRemove(InclPathDelim(ExtractTemplateDir),
    FileInfo.AbsoluteName, true);

  if IsWild(DestinationRelativeFileName, '*setup_sdk.sh', true) or
     IsWild(DestinationRelativeFileName, '*~', true) or
     SameFileName(ExtractFileName(DestinationRelativeFileName), '.DS_Store') or
     SameFileName(ExtractFileName(DestinationRelativeFileName), 'thumbs.db') then
  begin
    // if Verbose then
    //   Writeln('Ignoring template file: ' + DestinationRelativeFileName);
    Exit;
  end;

  StringReplaceAllVar(DestinationRelativeFileName, 'cge_project_name', Name);

  DestinationFileName := ExtractTemplateDestinationPath + DestinationRelativeFileName;

  ExtractTemplateFile(FileInfo.AbsoluteName, DestinationFileName,
    DestinationRelativeFileName,
    ExtractTemplateOverrideExisting);
end;

procedure TCastleProject.ExtractTemplateFile(
  const SourceFileName, DestinationFileName, DestinationRelativeFileName: string;
  const OverrideExisting: boolean);
var
  DestinationRelativeFileNameSlashes, Contents, Ext: string;
  BinaryFile: boolean;
begin
  if SameText(DestinationRelativeFileName, 'README.md') then
    Exit; // do not copy README.md, most services define it and would just overwrite each other

  if (not OverrideExisting) and RegularFileExists(DestinationFileName) then
  begin
    DestinationRelativeFileNameSlashes := StringReplace(
      DestinationRelativeFileName, '\', '/', [rfReplaceAll]);

    if SameText(DestinationRelativeFileNameSlashes, Name + '/AppDelegate.m') then
      MergeIOSAppDelegate(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'Podfile') then
      MergeIOSPodfile(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, Name + '/' + Name + '-Info.plist') then
      MergeIOSInfoPlist(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'app/src/main/AndroidManifest.xml') then
      MergeAndroidManifest(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'app/src/main/res/values/strings.xml') then
      MergeStringsXml(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'app/src/main/java/net/sourceforge/castleengine/MainActivity.java') then
      MergeAndroidMainActivity(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'app/src/main/jni/Android.mk') or
       SameText(DestinationRelativeFileNameSlashes, 'app/src/main/custom-proguard-project.txt') then
      MergeAppend(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'app/build.gradle') then
      MergeBuildGradle(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
    if SameText(DestinationRelativeFileNameSlashes, 'build.gradle') then
      MergeBuildGradle(SourceFileName, DestinationFileName, @ReplaceMacros)
    else
      WritelnWarning('Template not overwriting custom ' + DestinationRelativeFileName);

    Exit;
  end;

  Ext := ExtractFileExt(SourceFileName);
  BinaryFile := SameText(Ext, '.so') or SameText(Ext, '.jar');
  CheckForceDirectories(ExtractFilePath(DestinationFileName));

  try
    if BinaryFile then
    begin
      CheckCopyFile(SourceFileName, DestinationFileName);
    end else
    begin
      Contents := FileToString(FilenameToURISafe(SourceFileName));
      Contents := ReplaceMacros(Contents);
      StringToFile(FilenameToURISafe(DestinationFileName), Contents);
    end;
  except
    on E: EFOpenError do
    begin
      Writeln('Cannot open a template file.');
      Writeln(SErrDataDir);
      raise;
    end;
  end;
end;

function TCastleProject.OutputPath: string;
begin
  if OutputPathBase = '' then
    Result := Path
  else
  begin
    Result := InclPathDelim(ExpandFileName(OutputPathBase));
    CheckForceDirectories(Result);
  end;
end;

procedure TCastleProject.CopyData(OutputDataPath: string; const TargetPlatform: TCastlePlatform);
var
  I: Integer;
  FileFrom, FileTo: string;
  Files: TCastleStringList;
begin
  OutputDataPath := InclPathDelim(OutputDataPath);
  ForceDirectories(OutputDataPath);

  Files := PackageFiles(true, TargetPlatform);
  try
    for I := 0 to Files.Count - 1 do
    begin
      FileFrom := DataPath + Files[I];
      FileTo := OutputDataPath + Files[I];
      SmartCopyFile(FileFrom, FileTo);
      if Verbose then
        Writeln('Packaging data file: ' + Files[I]);
    end;
  finally FreeAndNil(Files) end;

  GenerateDataInformation(OutputDataPath);
end;

function TCastleProject.PackageOutput(const FileName: String): Boolean;
var
  OS: TOS;
  CPU: TCPU;
  PackageFormat: TPackageFormatNoDefault;
  HasVersion: Boolean;
begin
  for OS in TOS do
    for CPU in TCPU do
      // TODO: This will not exclude output of packaging with pfDirectory
      for PackageFormat in TPackageFormatNoDefault do
        for HasVersion in Boolean do
          if OSCPUSupported[OS, CPU] then
            if SameFileName(FileName, PackageName(OS, CPU, PackageFormat, HasVersion)) then
              Exit(true);

  for HasVersion in Boolean do
    if SameFileName(FileName, SourcePackageName(HasVersion)) then
      Exit(true);

  if { avoid Android packages }
     SameFileName(FileName, Name + '-debug.apk') or
     SameFileName(FileName, Name + '-release.apk') or
     { do not pack AndroidAntProperties.txt with private stuff }
     SameFileName(FileName, 'AndroidAntProperties.txt') then
    Exit(true);

  Result := false;
end;

{ shortcut methods to acces Manifest.Xxx ------------------------------------- }

function TCastleProject.Version: TProjectVersion;
begin
  Result := Manifest.Version;
end;

function TCastleProject.QualifiedName: string;
begin
  Result := Manifest.QualifiedName;
end;

function TCastleProject.Dependencies: TDependencies;
begin
  Result := Manifest.Dependencies;
end;

function TCastleProject.Name: string;
begin
  Result := Manifest.Name;
end;

function TCastleProject.Path: string;
begin
  Result := Manifest.Path;
end;

function TCastleProject.DataExists: Boolean;
begin
  Result := Manifest.DataExists;
end;

function TCastleProject.DataPath: string;
begin
  Result := Manifest.DataPath;
end;

function TCastleProject.Caption: string;
begin
  Result := Manifest.Caption;
end;

function TCastleProject.Author: string;
begin
  Result := Manifest.Author;
end;

function TCastleProject.ExecutableName: string;
begin
  Result := Manifest.ExecutableName;
end;

function TCastleProject.FullscreenImmersive: boolean;
begin
  Result := Manifest.FullscreenImmersive;
end;

function TCastleProject.ScreenOrientation: TScreenOrientation;
begin
  Result := Manifest.ScreenOrientation;
end;

function TCastleProject.AndroidCompileSdkVersion: Cardinal;
begin
  Result := Manifest.AndroidCompileSdkVersion;
end;

function TCastleProject.AndroidMinSdkVersion: Cardinal;
begin
  Result := Manifest.AndroidMinSdkVersion;
end;

function TCastleProject.AndroidTargetSdkVersion: Cardinal;
begin
  Result := Manifest.AndroidTargetSdkVersion;
end;

function TCastleProject.AndroidProjectType: TAndroidProjectType;
begin
  Result := Manifest.AndroidProjectType;
end;

function TCastleProject.Icons: TImageFileNames;
begin
  Result := Manifest.Icons;
end;

function TCastleProject.LaunchImages: TImageFileNames;
begin
  Result := Manifest.LaunchImages;
end;

function TCastleProject.SearchPaths: TStringList;
begin
  Result := Manifest.SearchPaths;
end;

function TCastleProject.LibraryPaths: TStringList;
begin
  Result := Manifest.LibraryPaths;
end;

function TCastleProject.AndroidServices: TServiceList;
begin
  Result := Manifest.AndroidServices;
end;

function TCastleProject.IOSServices: TServiceList;
begin
  Result := Manifest.IOSServices;
end;

function TCastleProject.AssociateDocumentTypes: TAssociatedDocTypeList;
begin
  Result := Manifest.AssociateDocumentTypes;
end;

function TCastleProject.ListLocalizedAppName: TListLocalizedAppName;
begin
  Result := Manifest.ListLocalizedAppName;
end;

end.
