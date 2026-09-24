%%
% This code is for setting paths of BIDS data and SPM.
% Thus, this code must be run before running the other codes.

%%
clear;

% % % Please enter data path here >>>
pathBIDS = '<DATA_ROOT>/ds004562'; % <<<<<<<

pathCurrent = pwd;

tempFolder = 'temp';
dirSPM = cellstr(which('spm.m','-ALL'));
if length(dirSPM) >=1
    pathSPM = dirSPM{1}(1:end-6);
    if length(pathBIDS) >=1
        try cd(tempFolder); catch; mkdir(tempFolder); cd(tempFolder); end
        save tempFileForAnalysis pathSPM pathBIDS
    else
        error('Please enter data path in "pathBIDS" variable.');
    end
else
    error('SPM is not properly installed....');
end

cd(pathCurrent);
