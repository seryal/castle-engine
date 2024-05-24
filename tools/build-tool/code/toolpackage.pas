{
  Copyright 2014-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Packaging data in archives. }
unit ToolPackage;

{$I castleconf.inc}

interface

uses CastleUtils, CastleInternalAutoGenerated,
  ToolPackageFormat, ToolManifest, ToolArchitectures;

type
  { Package a project to a directory. }
  TPackageDirectory = class
  private
    TemporaryDir: String;
    FPath: String;
    FTopDirectoryName: String;

    { Absolute path (ends with path delimiter) under which you should
      store your files. They will end up being packaged,
      under TopDirectoryName. }
    property Path: String read FPath;
    property TopDirectoryName: String read FTopDirectoryName;
  public
    { Architecture of the binaries in final package.
      Right now only used by package format = pfDeb. }
    Cpu: TCpu;

    { Manifest of project used to make this.
      Right now only used by package format = pfDeb. }
    Manifest: TCastleManifest;

    { Create a package.

      @param(ATopDirectoryName is the name of the main directory that will
        be visible in the archive, it's usually just a project name.) }
    constructor Create(const ATopDirectoryName: String);
    destructor Destroy; override;

    { Add file to the package.

      @param SourceFileName Filename existing on disk right now, must be an absolute filename.

      @param DestinationFileName Name in package, must be relative within package.

      @param MakeExecutable Set the Unix executable bit on given file. }
    procedure Add(const SourceFileName, DestinationFileName: String;
      const MakeExecutable: Boolean = false);

    { Generate auto_generated/CastleDataInformation.xml file inside
      DataName subdirectory of the archive. }
    procedure AddDataInformation(const DataName: String);

    { Create final archive.
      It will be placed within PackageOutputPath.
      PackageFileName should contain only the file name, with an extension
      (like .zip or .deb) but without any directory parts. }
    procedure Make(const PackageOutputPath: String; const PackageFileName: String;
      const PackageFormat: TPackageFormatNoDefault);
  end;

{ Generate auto_generated/CastleDataInformation.xml file inside
  CurrentDataPath, if it exists.
  CurrentDataPath may but doesn't have to end with PathDelim. }
procedure GenerateDataInformation(const CurrentDataPath: String);

implementation

uses SysUtils, Process,
  CastleFilesUtils, CastleLog, CastleFindFiles, CastleUriUtils,
  CastleStringUtils, CastleInternalDirectoryInformation,
  ToolCommonUtils, ToolUtils, ToolDebian;

{ TPackageDirectory ---------------------------------------------------------- }

constructor TPackageDirectory.Create(const ATopDirectoryName: String);
begin
  inherited Create;
  FTopDirectoryName := ATopDirectoryName;

  TemporaryDir := CreateTemporaryDir;

  FPath := InclPathDelim(TemporaryDir) + TopDirectoryName;
  CheckForceDirectories(FPath);
  FPath += PathDelim;
end;

destructor TPackageDirectory.Destroy;
begin
  RemoveNonEmptyDir(TemporaryDir, true);
  inherited;
end;

procedure TPackageDirectory.Make(const PackageOutputPath: String;
  const PackageFileName: String; const PackageFormat: TPackageFormatNoDefault);
var
  FullPackageFileName: String;

  { Run zip/tar.gz/other command that makes archive called PackageFileName
    (should be a filename, without directory part, like 'myproject.zip' or 'myproject.tar.gz')
    in current directory, wherever it is run (we will run it in a temp directory).

    We will move the resulting file to FullPackageFileName
    (which should be absolute filename now). }
  procedure PackageCommand(const PackagingExeName: String; const PackagingParameters: array of String);
  var
    ProcessOutput, CommandExe: String;
    ProcessExitStatus: Integer;
  begin
    CommandExe := FindExe(PackagingExeName);
    if CommandExe = '' then
      raise Exception.CreateFmt('Cannot find "%s" program on $PATH. Make sure it is installed, and available on $PATH', [
        PackagingExeName
      ]);
    MyRunCommandIndir(TemporaryDir, CommandExe,
      PackagingParameters,
      ProcessOutput, ProcessExitStatus);

    if Verbose then
    begin
      Writeln('Executed package process, output:');
      Writeln(ProcessOutput);
    end;

    if ProcessExitStatus <> 0 then
      raise Exception.CreateFmt('Package process exited with error, status %d', [ProcessExitStatus]);

    CheckRenameFile(InclPathDelim(TemporaryDir) + PackageFileName, FullPackageFileName);
  end;

var
  PackageIsSingleFile: Boolean;
begin
  FullPackageFileName := CombinePaths(PackageOutputPath, PackageFileName);

  PackageIsSingleFile := PackageFormat in [pfZip, pfTarGz, pfDeb];

  { Clean previous package file/directory. }
  if PackageIsSingleFile then
    DeleteFile(FullPackageFileName)
  else
  if DirectoryExists(FullPackageFileName) then
    RemoveNonEmptyDir(FullPackageFileName);

  { Do the package-format-specific job. }
  case PackageFormat of
    pfZip      :
      //PackageCommand('zip', ['-q', '-r', PackageFileName, TopDirectoryName]);
      // Better use internal zip, that doesn't require any tool installed:
      ZipDirectory(FullPackageFileName, Path);
    pfTarGz    : PackageCommand('tar', ['czf', PackageFileName, TopDirectoryName]);
    pfDirectory:
      begin
        if DirectoryExists(FullPackageFileName) then
          RemoveNonEmptyDir(FullPackageFileName);
        CopyDirectory(Path, FullPackageFileName);
      end;
    pfDeb: PackageDebian(Path, PackageOutputPath, PackageFileName, Cpu, Manifest);
    else raise EInternalError.Create('TPackageDirectory.Make PackageFormat?');
  end;

  { Report success. }
  if PackageIsSingleFile then
    Writeln('Created package ' + PackageFileName + ', size: ', SizeToStr(FileSize(FullPackageFileName)))
  else
    Writeln('Created directory ' + PackageFileName);
end;

procedure TPackageDirectory.Add(const SourceFileName, DestinationFileName: String;
  const MakeExecutable: Boolean);
begin
  SmartCopyFile(SourceFileName, Path + DestinationFileName);
  WritelnVerbose('Package file: ' + DestinationFileName);

  if MakeExecutable then
  begin
    { For OSes where chmod matters, make sure to set it before packing }
    WritelnVerbose('Setting Unix executable permissions: ' + DestinationFileName);
    DoMakeExecutable(Path + DestinationFileName);
  end;
end;

procedure TPackageDirectory.AddDataInformation(const DataName: String);
begin
  GenerateDataInformation(Path + DataName);
end;

{ global --------------------------------------------------------------------- }

procedure GenerateDataInformation(const CurrentDataPath: String);
var
  DataInformationDir, DataInformationFileName: String;
  DataInformation: TDirectoryInformation;
  DirsCount, FilesCount, FilesSize: QWord;
begin
  if DirectoryExists(CurrentDataPath) then
  begin
    DataInformationDir := InclPathDelim(CurrentDataPath) + 'auto_generated';
    CheckForceDirectories(DataInformationDir);
    DataInformationFileName := DataInformationDir + PathDelim + 'CastleDataInformation.xml';
    { Do not include CastleDataInformation.xml itself on a list of existing files,
      since we don't know it's size yet. }
    DeleteFile(DataInformationFileName);

    DataInformation := TDirectoryInformation.Create;
    try
      DataInformation.Generate(FilenameToUriSafe(CurrentDataPath));
      DataInformation.SaveToFile(FilenameToUriSafe(DataInformationFileName));

      DataInformation.Sum(DirsCount, FilesCount, FilesSize);
      Writeln('Generated CastleDataInformation.xml.');
      Writeln(Format('Project data contains %d directories, %d files, total (uncompressed) size %s.',
        [DirsCount, FilesCount, SizeToStr(FilesSize)]));
    finally FreeAndNil(DataInformation) end;
  end;
end;

end.
