%% initialize
clear; clc;

pathCurrent = pwd;
cd ../temp
load('tempFileForAnalysis.mat');

cd(pathBIDS);
cd derivatives
pathDeriv = pwd;

cd(pathDeriv);
cd('spm-preproc'); % For saving preprocessed file from SPM
pathPrepFile = pwd;
prepSubjFolders = dir('sub*');

cd(pathDeriv);
mkdir('conn-art'); cd('conn-art');
pathConn = pwd;

%%
cd([pathBIDS filesep prepSubjFolders(1).name filesep 'ses-02fmri' filesep 'func']);
jsonFile = dir('sub*_bold.json');

fname = [jsonFile.folder filesep jsonFile.name];
fid = fopen(fname); raw = fread(fid,inf); str = char(raw'); fclose(fid); 
funcJsonScan = jsondecode(str);
rt = funcJsonScan.RepetitionTime;

%% Create CONN project
batch.filename = [pathConn filesep 'conn_MotorRep_MVPA.mat'];
batch.Setup.isnew = 1; % Create new project
batch.Setup.done = 0; % Setup is not done yet
batch.Setup.nsubjects = length(prepSubjFolders);
batch.Setup.RT = rt;
batch.Setup.acquisitiontype = 1; % This is continuous acquisition

%% Upload functional (slice-timing corrected files & exclude the initial practice period)
taskNames = {'Pre', 'Training', 'Post'};

numStartSub2021 = 16;

onsets = zeros(50,3);
durations = zeros(50,3);
endDuration = zeros(50,3);
numScanIncludeStarts = zeros(50,3);

for nsub=1:length(prepSubjFolders)
    cd([prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'func']);
    funcFilePath = conn_dir(['au*bold.nii']);

    batch.Setup.functionals{nsub}=funcFilePath; 
end 

%% Upload Covariates
batch.Setup.covariates.names={'realignment'};
taskNames = {'Pre', 'Training', 'Post'};
for nsub=1:length(prepSubjFolders) %note: each subject's data is defined by three sessions and one single (4d) file per session
    cd([prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'func']);
    rpFile = dir(['rp*.txt']);
    batch.Setup.covariates.files{1}{nsub}=[rpFile.folder filesep rpFile.name]; 
end 

cd(pathCurrent);

%% Execute batch
conn_batch(batch);

%% Execure ART pipeline
clear batch

batch.filename = [pathConn filesep 'conn_MotorRep_MVPA.mat'];
batch.Setup.isnew = 0;
batch.Setup.done = 0;

batch.Setup.preprocessing.steps = {'functional_art'};
conn_batch(batch);