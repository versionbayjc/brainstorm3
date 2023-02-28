function tutorial_fem_charm(tutorial_dir)
% TUTORIAL_FEM_CHARM: Script that reproduces the online tutorial "FEM tutorial: MEG/EEG Median nerve stimulation (charm)"
%
% REFERENCE:
%     https://neuroimage.usc.edu/brainstorm/Tutorials/FemMedianNerveCharm
%
% INPUTS: 
%     tutorial_dir: Directory where the sample_fem.zip file has been unzipped

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c) University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Author: Francois Tadel, 2021-2023


% ===== FILES TO IMPORT =====
% You have to specify the folder in which the tutorial dataset is unzipped
if (nargin == 0) || isempty(tutorial_dir) || ~file_exist(tutorial_dir)
    error('The first argument must be the full path to the tutorial dataset folder.');
end
% Build the path of the files to import
T1Nii  = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-mri', 'anat', 'sub-fem01_ses-mri_T1w.nii.gz');
T2Nii  = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-mri', 'anat', 'sub-fem01_ses-mri_T2w.nii.gz');
DwiNii = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-mri', 'dwi', 'sub-fem01_ses-mri_dwi.nii.gz');
DwiBval = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-mri', 'dwi', 'sub-fem01_ses-mri_dwi.bval');
DwiBvec = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-mri', 'dwi', 'sub-fem01_ses-mri_dwi.bvec');
FifFile = fullfile(tutorial_dir, 'sample_fem', 'sub-fem01', 'ses-meg', 'meg', 'sub-fem01_ses-meg_task-mediannerve_run-01_proc-tsss_meg.fif');
% Check if the folder contains the required files
if ~file_exist(T1Nii) || ~file_exist(FifFile)
    error(['The folder ' tutorial_dir ' does not contain the folder from the file sample_fem.zip.']);
end
% Subject name
SubjectName = 'Subject01';
% Latency of interest
Latency = 0.022;


% ===== CHECK SOFTWARE DEPENDENCIES =====
% Start brainstorm without the GUI
if ~brainstorm('status')
    brainstorm nogui
end
% SimNIBS 4 / charm
status = system('charm --version');
if (status ~= 0)
    error('SimNIBS is not installed or not added to the system path: the command "headreco" could not be found.');
end
% BrainSuite
if ~file_exist(bst_fullfile(bst_get('BrainSuiteDir'), 'bin'))
    error('BrainSuite is not configured in the Brainstorm preferences.');
end
% Iso2mesh
[isInstalled, errMsg] = bst_plugin('Install', 'iso2mesh', 0);
if ~isInstalled
    error(['Could not install plugin: iso2mesh' 10 errMsg]);
end


% ===== CREATE PROTOCOL =====
% The protocol name has to be a valid folder name (no spaces, no weird characters...)
ProtocolName = 'TutorialFem';
% Delete existing protocol
gui_brainstorm('DeleteProtocol', ProtocolName);
% Create new protocol
gui_brainstorm('CreateProtocol', ProtocolName, 0, 1);
% Start a new report
bst_report('Start');


%% ===== IMPORT ANATOMY =====
% ===== IMPORT MRI VOLUMES =====
% Create subject
[sSubject, iSubject] = db_add_subject(SubjectName, [], 0, 0);
% Import T1 MRI
T1File = import_mri(iSubject, T1Nii, 'ALL', 0, 0);
% Compute the MNI normalization
bst_normalize_mni(T1File);
% Import T2 MRI
T2File = import_mri(iSubject, T2Nii, 'ALL', 0, 0);
% Volumes are not registered: Register with SPM
mri_coregister(T2File, T1File, 'spm', 1);
% Delete the non-registered T2
file_delete(file_fullpath(T2File), 1);
db_reload_subjects(iSubject);
            
% ===== IMPORT DTI =====
% Process: Convert DWI to DTI (BrainSuite)
bst_process('CallProcess', 'process_dwi2dti', [], [], ...
    'subjectname', SubjectName, ...
    'dwifile',     {DwiNii, 'DWI-NII'}, ...
    'bvalfile',    {DwiBval, 'DWI-BVAL'}, ...
    'bvecfile',    {DwiBvec, 'DWI-BVEC'});

% ===== RUN SIMNIBS =====
% Process: Generate FEM mesh
bst_process('CallProcess', 'process_fem_mesh', [], [], ...
    'subjectname',   SubjectName, ...
    'method',        'simnibs4', ...  % SimNIBS:Call SimNIBS to segment and mesh the T1 (and T2) MRI.
    'nvertices',     15000, ...
    'zneck',         0);
% Select default cortex: Central / Low-resolution
[sSubject, iSubject, iCortex] = bst_get('SurfaceFile', bst_fullfile(SubjectName, 'tess_cortex_mid_low.mat'));
db_surface_default(iSubject, 'Cortex', iCortex);

% FEM mesh: Merge 12 tissues into 5 tissues
Fem12File = sSubject.Surface(sSubject.iFEM).FileName;
Fem5File = panel_femname('Edit', Fem12File, {'white', 'gray', 'csf', 'skull', 'scalp', 'scalp', 'skull', 'skull', 'csf', 'csf', '', ''});

% ===== REMESH WITH ISO2MESH =====
% Part skipped because:
% 1) Not needed: DUNEuro works with cavities in this case
% 2) No process call for: Extract surfaces (import_femlayers)
% 3) Remeshing with iso2mesh doesn't work...

% ===== COMPUTE FEM TENSORS =====
% Process: Compute FEM tensors
bst_process('CallProcess', 'process_fem_tensors', [], [], ...
    'subjectname', SubjectName, ...
    'femcond',     struct(...
         'FemCond',         [0.14, 0.33, 1.79, 0.008, 0.43], ...
         'isIsotropic',     [0, 1, 1, 1, 1], ...
         'AnisoMethod',     'ema+vc', ...
         'SimRatio',        10, ...
         'SimConstrMethod', 'wolters'));

% ===== COMPUTE BEM SURFACES =====
% Process: Generate BEM surfaces
bst_process('CallProcess', 'process_generate_bem', [], [], ...
    'subjectname', SubjectName, ...
    'nscalp',      1922, ...
    'nouter',      1922, ...
    'ninner',      1922, ...
    'thickness',   4);


%% ===== ACCESS THE RECORDINGS =====
% Process: Create link to raw file
sFilesRaw = bst_process('CallProcess', 'process_import_data_raw', [], [], ...
    'subjectname',    SubjectName, ...
    'datafile',       {FifFile, 'FIF'}, ...
    'channelreplace', 0, ...
    'channelalign',   1, ...    % Automatic registration with digitized head points
    'evtmode',        'value');

% Process: Events: Read from channel
sFilesRaw = bst_process('CallProcess', 'process_evt_read', sFilesRaw, [], ...
    'stimchan',  'STI101', ...
    'trackmode', 1, ...  % Value: detect the changes of channel value
    'zero',      0);

% Process: Project electrodes on scalp
bst_process('CallProcess', 'process_channel_project', sFilesRaw, []);

% Process: Snapshot: Sensors/MRI registration
bst_process('CallProcess', 'process_snapshot', sFilesRaw, [], ...
    'target',   1, ...  % Sensors/MRI registration
    'modality', 1, ...  % MEG (All)
    'orient',   1, ...  % left
    'Comment',  'MEG/MRI Registration');
% Process: Snapshot: Sensors/MRI registration
bst_process('CallProcess', 'process_snapshot', sFilesRaw, [], ...
    'target',   1, ...  % Sensors/MRI registration
    'modality', 4, ...  % EEG
    'orient',   1, ...  % left
    'Comment',  'EEG/MRI Registration');


%% ===== PRE-PROCESSING =====
% Process: Power spectrum density (Welch)
sFilesPsd = bst_process('CallProcess', 'process_psd', sFilesRaw, [], ...
    'timewindow',  [18, 148.999], ...
    'win_length',  5, ...
    'win_overlap', 50, ...
    'units',       'physical', ...  % Physical: U2/Hz
    'sensortypes', 'MEG, EEG', ...
    'win_std',     0, ...
    'edit',        struct(...
         'Comment',         'Power', ...
         'TimeBands',       [], ...
         'Freqs',           [], ...
         'ClusterFuncTime', 'none', ...
         'Measure',         'power', ...
         'Output',          'all', ...
         'SaveKernel',      0));
     
% Process: Snapshot: Frequency spectrum
bst_process('CallProcess', 'process_snapshot', sFilesPsd, [], ...
    'target',   10, ...  % Frequency spectrum
    'Comment',  'Power spectrum density');
     
% Process: Band-pass:20Hz-250Hz
sFilesBand = bst_process('CallProcess', 'process_bandpass', sFilesRaw, [], ...
    'sensortypes', 'MEG, EEG', ...
    'highpass',    20, ...
    'lowpass',     250, ...
    'tranband',    0, ...
    'attenuation', 'strict', ...  % 60dB
    'ver',         '2019', ...  % 2019
    'mirror',      0, ...
    'read_all',    0);

% Process: Notch filter: 60Hz 120Hz 180Hz
sFilesClean = bst_process('CallProcess', 'process_notch', sFilesBand, [], ...
    'sensortypes', 'MEG, EEG', ...
    'freqlist',    [60, 120, 180], ...
    'cutoffW',     2, ...
    'useold',      0, ...
    'read_all',    0);

% Process: Delete selected files
bst_process('CallProcess', 'process_delete', [sFilesRaw, sFilesBand], [], ...
    'target', 2);  % Delete selected folders

% Process: Re-reference EEG
bst_process('CallProcess', 'process_eegref', sFilesClean, [], ...
    'eegref',      'AVERAGE', ...
    'sensortypes', 'EEG');


%% ===== IMPORT RECORDINGS =====
% Process: Import MEG/EEG: Events
sFilesEpochs = bst_process('CallProcess', 'process_import_data_event', sFilesClean, [], ...
    'subjectname', SubjectName, ...
    'condition',   '', ...
    'eventname',   '2', ...
    'timewindow',  [18, 148.999], ...
    'epochtime',   [-0.1, 0.2], ...
    'createcond',  0, ...
    'ignoreshort', 1, ...
    'usectfcomp',  1, ...
    'usessp',      1, ...
    'freq',        [], ...
    'baseline',    []);

% Process: Average: By trial group (folder average)
sFilesAvg = bst_process('CallProcess', 'process_average', sFilesEpochs, [], ...
    'avgtype',       5, ...  % By trial group (folder average)
    'avg_func',      1, ...  % Arithmetic average:  mean(x)
    'weighted',      0, ...
    'keepevents',    0);

% Process: Snapshot: Recordings time series
bst_process('CallProcess', 'process_snapshot', sFilesAvg, [], ...
    'target',   5, ...  % Recordings time series
    'modality', 4, ...  % EEG
    'Comment',  'EEG ERP');
% Process: Snapshot: Recordings topography (contact sheet)
bst_process('CallProcess', 'process_snapshot', sFilesAvg, [], ...
    'target',   6, ...  % Recordings topography (ont time)
    'modality', 4, ...  % EEG
    'time',     Latency, ...
    'Comment',  'EEG ERP');
% Process: Snapshot: Recordings time series
bst_process('CallProcess', 'process_snapshot', sFilesAvg, [], ...
    'target',   5, ...  % Recordings time series
    'modality', 1, ...  % MEG (All)
    'Comment',  'MEG ERF');
% Process: Snapshot: Recordings topography (contact sheet)
bst_process('CallProcess', 'process_snapshot', sFilesAvg, [], ...
    'target',   6, ...  % Recordings topography (ont time)
    'modality', 1, ...  % MEG (All)
    'time',     Latency, ...
    'Comment',  'MEG ERF');


%% ===== NOISE COVARIANCE =====
% Process: Compute covariance (noise or data)
bst_process('CallProcess', 'process_noisecov', sFilesEpochs, [], ...
    'baseline',       [-0.1, -0.01], ...
    'sensortypes',    'MEG, EEG', ...
    'target',         1, ...  % Noise covariance     (covariance over baseline time window)
    'dcoffset',       1, ...  % Block by block, to avoid effects of slow shifts in data
    'replacefile',    1);  % Replace


%% ===== FORWARD: FEM EEG DTI =====
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'DUNEuro FEM EEG DTI', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         1, ...  % 
    'eeg',         4, ...  % DUNEuro FEM
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'duneuro',     struct(...
         'FemCond',             [], ...
         'FemSelect',           [1, 1, 1, 1, 1], ...
         'UseTensor',           1, ...
         'Isotropic',           1, ...
         'SrcShrink',           0, ...
         'SrcForceInGM',        0, ...
         'FemType',             'fitted', ...
         'SolverType',          'cg', ...
         'GeometryAdapted',     0, ...
         'Tolerance',           1e-08, ...
         'ElecType',            'normal', ...
         'MegIntorderadd',      0, ...
         'MegType',             'physical', ...
         'SolvSolverType',      'cg', ...
         'SolvPrecond',         'amg', ...
         'SolvSmootherType',    'ssor', ...
         'SolvIntorderadd',     0, ...
         'DgSmootherType',      'ssor', ...
         'DgScheme',            'sipg', ...
         'DgPenalty',           20, ...
         'DgEdgeNormType',      'houston', ...
         'DgWeights',           1, ...
         'DgReduction',         1, ...
         'SolPostProcess',      1, ...
         'SolSubstractMean',    0, ...
         'SolSolverReduction',  1e-10, ...
         'SrcModel',            'venant', ...
         'SrcIntorderadd',      0, ...
         'SrcIntorderadd_lb',   2, ...
         'SrcNbMoments',        3, ...
         'SrcRefLen',           20, ...
         'SrcWeightExp',        1, ...
         'SrcRelaxFactor',      6, ...
         'SrcMixedMoments',     1, ...
         'SrcRestrict',         1, ...
         'SrcInit',             'closest_vertex', ...
         'BstSaveTransfer',     0, ...
         'BstEegTransferFile',  'eeg_transfer.dat', ...
         'BstMegTransferFile',  'meg_transfer.dat', ...
         'BstEegLfFile',        'eeg_lf.dat', ...
         'BstMegLfFile',        'meg_lf.dat', ...
         'UseIntegrationPoint', 1, ...
         'EnableCacheMemory',   0, ...
         'MegPerBlockOfSensor', 0), ...
    'channelfile', '');
% Process: Compute sources [2018]
sSrcEegFemDti = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: EEG FEM DTI', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'EEG'}}));
% Process: Dipole scanning
sDipEegFemDti = bst_process('CallProcess', 'process_dipole_scanning', sSrcEegFemDti, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== FORWARD: FEM MEG DTI =====
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'DUNEuro FEM MEG DTI', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         5, ...  % DUNEuro FEM
    'eeg',         1, ...  % 
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'duneuro',     struct(...
         'FemCond',             [], ...
         'FemSelect',           [1, 1, 1, 0, 0], ...
         'UseTensor',           1, ...
         'Isotropic',           1, ...
         'SrcShrink',           0, ...
         'SrcForceInGM',        0, ...
         'FemType',             'fitted', ...
         'SolverType',          'cg', ...
         'GeometryAdapted',     0, ...
         'Tolerance',           1e-08, ...
         'ElecType',            'normal', ...
         'MegIntorderadd',      0, ...
         'MegType',             'physical', ...
         'SolvSolverType',      'cg', ...
         'SolvPrecond',         'amg', ...
         'SolvSmootherType',    'ssor', ...
         'SolvIntorderadd',     0, ...
         'DgSmootherType',      'ssor', ...
         'DgScheme',            'sipg', ...
         'DgPenalty',           20, ...
         'DgEdgeNormType',      'houston', ...
         'DgWeights',           1, ...
         'DgReduction',         1, ...
         'SolPostProcess',      1, ...
         'SolSubstractMean',    0, ...
         'SolSolverReduction',  1e-10, ...
         'SrcModel',            'venant', ...
         'SrcIntorderadd',      0, ...
         'SrcIntorderadd_lb',   2, ...
         'SrcNbMoments',        3, ...
         'SrcRefLen',           20, ...
         'SrcWeightExp',        1, ...
         'SrcRelaxFactor',      6, ...
         'SrcMixedMoments',     1, ...
         'SrcRestrict',         1, ...
         'SrcInit',             'closest_vertex', ...
         'BstSaveTransfer',     0, ...
         'BstEegTransferFile',  'eeg_transfer.dat', ...
         'BstMegTransferFile',  'meg_transfer.dat', ...
         'BstEegLfFile',        'eeg_lf.dat', ...
         'BstMegLfFile',        'meg_lf.dat', ...
         'UseIntegrationPoint', 1, ...
         'EnableCacheMemory',   0, ...
         'MegPerBlockOfSensor', 0), ...
    'channelfile', '');
% Process: Compute sources [2018]
sSrcMegFemDti = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: MEG FEM DTI', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG GRAD', 'MEG MAG'}}));
% Process: Dipole scanning
sDipMegFemDti = bst_process('CallProcess', 'process_dipole_scanning', sSrcMegFemDti, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== FORWARD: FEM EEG ISO =====
% Get updated subject structure
sSubject = bst_get('Subject', iSubject);
% Get FEM file
FemFile = file_fullpath(sSubject.Surface(sSubject.iFEM).FileName);
% Remove tensors
process_fem_tensors('ClearTensors', FemFile);
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'DUNEuro FEM EEG ISO', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         1, ...  % 
    'eeg',         4, ...  % DUNEuro FEM
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'duneuro',     struct(...
         'FemCond',             [0.14, 0.33, 1.79, 0.008, 0.43], ...
         'FemSelect',           [1, 1, 1, 1, 1], ...
         'UseTensor',           0, ...
         'Isotropic',           1, ...
         'SrcShrink',           0, ...
         'SrcForceInGM',        0, ...
         'FemType',             'fitted', ...
         'SolverType',          'cg', ...
         'GeometryAdapted',     0, ...
         'Tolerance',           1e-08, ...
         'ElecType',            'normal', ...
         'MegIntorderadd',      0, ...
         'MegType',             'physical', ...
         'SolvSolverType',      'cg', ...
         'SolvPrecond',         'amg', ...
         'SolvSmootherType',    'ssor', ...
         'SolvIntorderadd',     0, ...
         'DgSmootherType',      'ssor', ...
         'DgScheme',            'sipg', ...
         'DgPenalty',           20, ...
         'DgEdgeNormType',      'houston', ...
         'DgWeights',           1, ...
         'DgReduction',         1, ...
         'SolPostProcess',      1, ...
         'SolSubstractMean',    0, ...
         'SolSolverReduction',  1e-10, ...
         'SrcModel',            'venant', ...
         'SrcIntorderadd',      0, ...
         'SrcIntorderadd_lb',   2, ...
         'SrcNbMoments',        3, ...
         'SrcRefLen',           20, ...
         'SrcWeightExp',        1, ...
         'SrcRelaxFactor',      6, ...
         'SrcMixedMoments',     1, ...
         'SrcRestrict',         1, ...
         'SrcInit',             'closest_vertex', ...
         'BstSaveTransfer',     0, ...
         'BstEegTransferFile',  'eeg_transfer.dat', ...
         'BstMegTransferFile',  'meg_transfer.dat', ...
         'BstEegLfFile',        'eeg_lf.dat', ...
         'BstMegLfFile',        'meg_lf.dat', ...
         'UseIntegrationPoint', 1, ...
         'EnableCacheMemory',   0, ...
         'MegPerBlockOfSensor', 0), ...
    'channelfile', '');
% Process: Compute sources [2018]
sSrcEegFemIso = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: EEG FEM ISO', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'EEG'}}));
% Process: Dipole scanning
sDipEegFemIso = bst_process('CallProcess', 'process_dipole_scanning', sSrcEegFemIso, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== FORWARD: FEM MEG ISO =====
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'DUNEuro FEM MEG ISO', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         5, ...  % DUNEuro FEM
    'eeg',         1, ...  % 
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'duneuro',     struct(...
         'FemCond',             [0.14, 0.33, 1.79, 0.008, 0.43], ...
         'FemSelect',           [1, 1, 1, 0, 0], ...
         'UseTensor',           0, ...
         'Isotropic',           1, ...
         'SrcShrink',           0, ...
         'SrcForceInGM',        0, ...
         'FemType',             'fitted', ...
         'SolverType',          'cg', ...
         'GeometryAdapted',     0, ...
         'Tolerance',           1e-08, ...
         'ElecType',            'normal', ...
         'MegIntorderadd',      0, ...
         'MegType',             'physical', ...
         'SolvSolverType',      'cg', ...
         'SolvPrecond',         'amg', ...
         'SolvSmootherType',    'ssor', ...
         'SolvIntorderadd',     0, ...
         'DgSmootherType',      'ssor', ...
         'DgScheme',            'sipg', ...
         'DgPenalty',           20, ...
         'DgEdgeNormType',      'houston', ...
         'DgWeights',           1, ...
         'DgReduction',         1, ...
         'SolPostProcess',      1, ...
         'SolSubstractMean',    0, ...
         'SolSolverReduction',  1e-10, ...
         'SrcModel',            'venant', ...
         'SrcIntorderadd',      0, ...
         'SrcIntorderadd_lb',   2, ...
         'SrcNbMoments',        3, ...
         'SrcRefLen',           20, ...
         'SrcWeightExp',        1, ...
         'SrcRelaxFactor',      6, ...
         'SrcMixedMoments',     1, ...
         'SrcRestrict',         1, ...
         'SrcInit',             'closest_vertex', ...
         'BstSaveTransfer',     0, ...
         'BstEegTransferFile',  'eeg_transfer.dat', ...
         'BstMegTransferFile',  'meg_transfer.dat', ...
         'BstEegLfFile',        'eeg_lf.dat', ...
         'BstMegLfFile',        'meg_lf.dat', ...
         'UseIntegrationPoint', 1, ...
         'EnableCacheMemory',   0, ...
         'MegPerBlockOfSensor', 0), ...
    'channelfile', '');
% Process: Compute sources [2018]
sSrcMegFemIso = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: MEG FEM ISO', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG GRAD', 'MEG MAG'}}));
% Process: Dipole scanning
sDipMegFemIso = bst_process('CallProcess', 'process_dipole_scanning', sSrcMegFemIso, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== FORWARD: BEM EEG =====
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'OpenMEEG BEM EEG', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         1, ...  % 
    'eeg',         3, ...  % OpenMEEG BEM
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'openmeeg',    struct(...
         'BemSelect',    [1, 1, 1], ...
         'BemCond',      [1, 0.0125, 1], ...
         'BemNames',     {{'Scalp', 'Skull', 'Brain'}}, ...
         'BemFiles',     {{}}, ...
         'isAdjoint',    0, ...
         'isAdaptative', 1, ...
         'isSplit',      0, ...
         'SplitLength',  4000), ...
    'channelfile', '');
% Process: Compute sources [2018]
sSrcEegBem = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: EEG BEM', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'EEG'}}));
% Process: Dipole scanning
sDipEegBem = bst_process('CallProcess', 'process_dipole_scanning', sSrcEegBem, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== FORWARD: OS MEG =====
% Process: Compute head model
bst_process('CallProcess', 'process_headmodel', sFilesAvg, [], ...
    'Comment',     'OS MEG', ...
    'sourcespace', 1, ...  % Cortex surface
    'meg',         3, ...  % Overlapping spheres
    'eeg',         1, ...  % 
    'ecog',        1, ...  % 
    'seeg',        1, ...  % 
    'channelfile', '');
% Process: Compute sources [2018]
sSrcMegOs = bst_process('CallProcess', 'process_inverse_2018', sFilesAvg, [], ...
    'output',  1, ...  % Kernel only: shared
    'inverse', struct(...
         'Comment',        'Dipoles: MEG OS', ...
         'InverseMethod',  'gls', ...
         'InverseMeasure', 'performance', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       1, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'median', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'rms', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'MEG GRAD', 'MEG MAG'}}));
% Process: Dipole scanning
sDipMegOs = bst_process('CallProcess', 'process_dipole_scanning', sSrcMegOs, [], ...
    'timewindow', [Latency, Latency], ...
    'scouts',     {});


%% ===== MERGE DIPOLES =====
% sDipEegFemDti, sDipMegFemDti, sDipEegFemIso, sDipMegFemIso, sDipEegBem, sDipMegOs
% FEM DTI: EEG vs MEG
% sDipFemDti = dipoles_merge({sDipEegFemDti.FileName, sDipMegFemDti.FileName});


% Save and display report
ReportFile = bst_report('Save', []);
bst_report('Open', ReportFile);



