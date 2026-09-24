%% initialize
clear; clc;
disp('   Copy original files >> ');

pathCurrent = pwd;
cd ../temp
load('tempFileForAnalysis.mat');

cd(pathBIDS);
cd derivatives

dirPrep = 'spm-preproc';
mkdir(dirPrep); cd(dirPrep);
pathPrep = pwd;

cd(pathCurrent);

%% make directories

BIDS = spm_BIDS(pathBIDS);
subdir = BIDS.participants.participant_id;
subdir = subdir(~contains(subdir,'control'));
numSub = length(subdir);
spm_mkdir(pathPrep,subdir,{'anat','func'});

start_sub = 1;


%% Copy and gunzip T1 MPRAGE images
for nsub = start_sub:numSub
    disp([' ... copy T1: sub-' num2str(nsub,'%02d')]);
    f = spm_BIDS(BIDS,'data','sub',num2str(nsub,'%02d'),'modality','anat','type','T1w');
    spm_copy(f, fullfile(pathPrep,subdir{nsub},'anat'), 'gunzip',true);
end

%% Copy and gunzip fMRI images
for nsub = start_sub:numSub
    disp([' ... copy BOLD: sub-' num2str(nsub,'%02d')]);
    f = spm_BIDS(BIDS,'data','sub',num2str(nsub,'%02d'),'modality', 'func','type','bold');
    spm_copy(f, fullfile(pathPrep,subdir{nsub},'func'), 'gunzip',true);
end

%% End
cd(pathCurrent);