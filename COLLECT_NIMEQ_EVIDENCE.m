% Collect existing NIMEQ records into a separate ZIP for review.
% Save this script outside the experiment code folder, for example Downloads.
% Run it while the working nimeq_config.m is on the MATLAB path.
% Source files, source datasets, models and original result folders are unchanged.
% Verification writes only to the exported copies. No model is trained.
nimeqEvidenceZip = collect_nimeq_evidence();
fprintf('\nUpload this evidence ZIP to the conversation:\n%s\n', nimeqEvidenceZip);

function zipFile = collect_nimeq_evidence()
    configFile = which('nimeq_config');
    if isempty(configFile)
        projectRoot = uigetdir(pwd, 'Select the code folder containing nimeq_config.m');
        assert(~isequal(projectRoot, 0), 'No code folder selected.');
        configFile = fullfile(projectRoot, 'nimeq_config.m');
        assert(isfile(configFile), 'Selected folder does not contain nimeq_config.m.');
        addpath(projectRoot);
    end
    projectRoot = fileparts(configFile);
    assert(isfile(fullfile(projectRoot, '+nimeq', 'verify_run.m')), ...
        'The working +nimeq/verify_run.m is missing.');

    knownRoots = {projectRoot, ...
        'C:\Research\NIMEQ_SACNet_Experiment_Code\NIMEQ_SACNet_Experiment_Code\NIMEQ_SACNet_Experiment_Code', ...
        'C:\Research\NIMEQ_SACNet_Experiment_Code\NIMEQ_SACNet_Experiment_Code', ...
        'C:\Research\NIMEQ_SACNet_Experiment_Code'};
    knownRoots = unique_roots(knownRoots);
    runNames = {'d7c41', 'd7m41', 'idw41'};
    expectedTasks = {{'DR7_binary'}, {'DR7_5class', 'DR7_7class'}, ...
        {'IDRiD_binary', 'IDRiD_5class'}};
    runFolders = cell(size(runNames));
    savedConfigs = cell(size(runNames));

    for i = 1:numel(runNames)
        runFolders{i} = locate_run(runNames{i}, knownRoots, projectRoot);
        d = load(fullfile(runFolders{i}, 'configuration.mat'), 'cfg');
        assert(isfield(d, 'cfg'), 'configuration.mat does not contain cfg.');
        assert(strcmp(char(string(d.cfg.experimentName)), runNames{i}), ...
            'The selected configuration is for another experiment.');
        assert(isequal(sort(string(d.cfg.tasks(:))), sort(string(expectedTasks{i}(:)))), ...
            'The selected experiment has different tasks than expected.');
        savedConfigs{i} = d.cfg;
        if isfield(d.cfg, 'projectRoot')
            knownRoots{end+1} = char(string(d.cfg.projectRoot)); %#ok<AGROW>
        end
        fprintf('Located %s: %s\n', runNames{i}, runFolders{i});
    end
    knownRoots = unique_roots(knownRoots);

    exportParent = fileparts(projectRoot);
    if ispc && numel(exportParent) > 55
        exportParent = uigetdir(fileparts(projectRoot), ...
            'Choose a short output folder for the evidence ZIP, for example F:\CIBM');
        assert(~isequal(exportParent, 0), 'No output folder selected.');
    end
    stamp = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyMMdd_HHmmss_SSS'));
    exportName = ['ne_' stamp];
    exportRoot = fullfile(exportParent, exportName);
    zipFile = fullfile(exportParent, ['NIMEQ_Evidence_' stamp '.zip']);
    assert(~isfolder(exportRoot) && ~isfile(zipFile), 'Export destination already exists.');
    mkdir(exportRoot);
    fprintf('\nCollecting records in a separate folder:\n%s\n', exportRoot);

    sourceRows = cell(0, 2);
    sourceIndex = 0;
    for i = 1:numel(knownRoots)
        root = knownRoots{i};
        if ~isfile(fullfile(root, 'nimeq_config.m'))
            continue;
        end
        sourceIndex = sourceIndex + 1;
        if same_path(root, projectRoot)
            label = 'current';
        else
            label = sprintf('previous_%02d', sourceIndex);
        end
        snapshot_source(root, fullfile(exportRoot, 'code', label));
        sourceRows(end+1,:) = {string(label), string(root)}; %#ok<AGROW>
        fprintf('Copied source snapshot: %s\n', root);
    end
    writetable(cell2table(sourceRows, 'VariableNames', {'snapshot', 'original_folder'}), ...
        fullfile(exportRoot, 'source_locations.csv'));

    originalZip = fullfile(projectRoot, 'NIMEQ_Working_Code_Review.zip');
    if isfile(originalZip)
        copy_one(originalZip, fullfile(exportRoot, 'original_upload', 'NIMEQ_Working_Code_Review.zip'));
    end
    collectorFile = [mfilename('fullpath') '.m'];
    if isfile(collectorFile)
        copy_one(collectorFile, fullfile(exportRoot, 'collection_tool', 'COLLECT_NIMEQ_EVIDENCE.m'));
    end

    omitted = cell(0, 4);
    summaries = struct([]);
    allPassed = true;
    for i = 1:numel(runNames)
        name = runNames{i};
        original = runFolders{i};
        exported = fullfile(exportRoot, 'runs', name);
        mkdir(exported);
        files = dir(fullfile(original, '**', '*'));
        files = files(~[files.isdir]);
        copied = 0;
        for j = 1:numel(files)
            file = fullfile(files(j).folder, files(j).name);
            relative = relative_name(file, original);
            [keep, reason] = include_run_file(relative);
            if keep
                copy_one(file, fullfile(exported, relative));
                copied = copied + 1;
                if mod(copied, 250) == 0
                    fprintf('Copied %s: %d evidence files\n', name, copied);
                end
            else
                omitted(end+1,:) = {string(name), string(relative), files(j).bytes, string(reason)}; %#ok<AGROW>
            end
        end
        fprintf('Copied %s: %d evidence files\n', name, copied);
        cfg = savedConfigs{i};
        collect_annotations(cfg, fullfile(exported, 'input_annotations'));
        info = struct('run', name, 'original_folder', original, ...
            'export_folder', ['runs/' name], 'profile', char(string(cfg.profile)), ...
            'seed', cfg.seed, 'tasks', {cellstr(string(cfg.tasks(:)))}, ...
            'spectral_normalization', logical(cfg.sac.spectralNormalization), ...
            'legacy_baselines', logical(cfg.legacyBaselines), ...
            'cnn_epochs', cfg.cnn.epochs, 'final_sac_epochs', cfg.sac.epochs, ...
            'cv_sac_epochs', cfg.search.fitnessEpochs, 'cv_folds', cfg.search.folds, ...
            'population', cfg.search.population, 'search_iterations', cfg.search.iterations, ...
            'table4_trials', cfg.search.table4Trials, 'verification_passed', false, ...
            'verification_checks', 0, 'verification_failed_checks', 0, ...
            'export_verification_folder', '', 'verification_error', '');
        try
            % Recheck the copied records. Original runs receive no new files.
            report = nimeq.verify_run(exported, false, false, false);
            info.verification_passed = logical(report.passed);
            info.verification_checks = report.checks;
            info.verification_failed_checks = report.failed_checks;
            info.export_verification_folder = strrep(relative_name(report.reportFolder, exportRoot), '\', '/');
            allPassed = allPassed && logical(report.passed);
        catch err
            info.verification_error = getReport(err, 'extended', 'hyperlinks', 'off');
            allPassed = false;
            fprintf('Export verification could not finish for %s: %s\n', name, err.message);
        end
        if isempty(summaries)
            summaries = info;
        else
            summaries(end+1) = info; %#ok<AGROW>
        end
    end
    writetable(cell2table(omitted, 'VariableNames', ...
        {'run', 'relative_file', 'original_bytes', 'omission_reason'}), ...
        fullfile(exportRoot, 'omitted_files.csv'));

    metadata = struct('created_utc', char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
        'purpose', 'Existing new-experiment records collected for code and results review', ...
        'current_source_root', projectRoot, 'matlab', version, 'release', version('-release'), ...
        'all_export_verifications_passed', allPassed, ...
        'source_images_rehashed', false, 'deep_cv_verification_performed', false, ...
        'original_files_modified', false, 'models_trained', false, 'runs', summaries);
    write_json_local(fullfile(exportRoot, 'collection_metadata.json'), metadata);
    write_readme(fullfile(exportRoot, 'READ_ME_FIRST.txt'));
    write_inventory(exportRoot);
    fprintf('\nCompressing the collected records...\n');
    zip(zipFile, exportName, exportParent);
    z = dir(zipFile);
    fprintf('Evidence ZIP size: %.1f MiB\n', z.bytes/1024^2);
    if allPassed
        fprintf('All three exported runs passed verification using the current verifier.\n');
    else
        fprintf('Some exported checks failed. The ZIP includes the diagnostics for review.\n');
    end
end

function folder = locate_run(name, roots, projectRoot)
    found = {};
    for i = 1:numel(roots)
        candidate = fullfile(roots{i}, 'results', name);
        if isfile(fullfile(candidate, 'configuration.mat'))
            found{end+1} = candidate; %#ok<AGROW>
        end
    end
    found = unique_roots(found);
    if numel(found) == 1
        folder = found{1};
    elseif numel(found) > 1
        [choice, ok] = listdlg('PromptString', ['Select the verified ' name ' run:'], ...
            'SelectionMode', 'single', 'ListString', found, 'ListSize', [780 180]);
        assert(ok, 'No run folder selected.');
        folder = found{choice};
    else
        folder = uigetdir(fullfile(projectRoot, 'results'), ...
            ['Locate the saved ' name ' folder containing configuration.mat']);
        assert(~isequal(folder, 0), 'Run-folder selection cancelled.');
    end
    assert(isfile(fullfile(folder, 'configuration.mat')), ...
        'The selected run folder must contain configuration.mat.');
end

function roots = unique_roots(roots)
    output = {};
    for i = 1:numel(roots)
        candidate = char(string(roots{i}));
        if isempty(candidate)
            continue;
        end
        if isfolder(candidate)
            f = java.io.File(candidate);
            candidate = char(f.getCanonicalPath());
        end
        repeated = false;
        for j = 1:numel(output)
            repeated = repeated || same_path(candidate, output{j});
        end
        if ~repeated
            output{end+1} = candidate; %#ok<AGROW>
        end
    end
    roots = output;
end

function yes = same_path(a, b)
    a = strrep(char(a), '\', '/');
    b = strrep(char(b), '\', '/');
    if ispc
        yes = strcmpi(a, b);
    else
        yes = strcmp(a, b);
    end
end

function snapshot_source(original, destination)
    mkdir(destination);
    for pattern = {'*.m', '*.md', '*.txt', '*.json'}
        files = dir(fullfile(original, pattern{1}));
        files = files(~[files.isdir]);
        for j = 1:numel(files)
            copy_one(fullfile(files(j).folder, files(j).name), ...
                fullfile(destination, files(j).name));
        end
    end
    folders = {'+nimeq', 'tests', 'docs', 'validation', 'published_reference', ...
        'reference_inputs', 'local_validation'};
    for i = 1:numel(folders)
        src = fullfile(original, folders{i});
        if isfolder(src)
            [ok, message] = copyfile(src, fullfile(destination, folders{i}));
            assert(ok, '%s', message);
        end
    end
end

function [keep, reason] = include_run_file(relative)
    normalized = lower(strrep(relative, '\', '/'));
    parts = strsplit(normalized, '/');
    [~, stem, extension] = fileparts(normalized);
    name = [stem extension];
    keep = false;
    reason = 'Optional binary cache or model; retained in the original run folder';
    if any(strcmp(parts, 'image_cache'))
        reason = 'Cached source image; source images are outside this evidence export';
        return;
    end
    if contains(name, '.tmp.') || endsWith(name, '.tmp')
        reason = 'Incomplete temporary file retained only in the original folder';
        return;
    end
    imageExtensions = {'.png', '.jpg', '.jpeg', '.tif', '.tiff', '.bmp'};
    if any(strcmp(parts, 'training_images')) && ismember(extension, imageExtensions)
        reason = 'Augmented training image; augmentation_ancestry.csv is included';
        return;
    end
    if ismember(name, {'raw_training_features.csv', 'raw_evaluation_features.csv'})
        reason = 'Optional large feature export retained in the original run folder';
        return;
    end
    if ismember(extension, {'.csv', '.json', '.log', '.txt', '.md', '.m', '.fig', '.png', '.pdf', '.svg'})
        keep = true;
        reason = '';
    elseif ismember(name, {'configuration.mat', 'fitness.mat', 'optimization_result.mat', ...
            'task_results.mat', 'table4_new_best_state.mat'})
        keep = true;
        reason = '';
    end
end

function collect_annotations(cfg, destination)
    % Small original label files support comparison with the saved manifests.
    % Image data are not copied and no spreadsheet is rewritten.
    if any(startsWith(string(cfg.tasks), 'DR7')) && isfolder(cfg.data.dr7Root)
        files = dir(fullfile(cfg.data.dr7Root, '**', '*.xlsx'));
        for i = 1:numel(files)
            if contains(lower(files(i).name), 'annotation')
                path = fullfile(files(i).folder, files(i).name);
                copy_one(path, fullfile(destination, 'DR7', relative_name(path, cfg.data.dr7Root)));
            end
        end
    end
    if any(startsWith(string(cfg.tasks), 'IDRiD')) && isfolder(cfg.data.idridRoot)
        files = dir(fullfile(cfg.data.idridRoot, '**', '*.csv'));
        for i = 1:numel(files)
            name = lower(files(i).name);
            if contains(name, 'label') && (contains(name, 'training') || contains(name, 'testing'))
                path = fullfile(files(i).folder, files(i).name);
                copy_one(path, fullfile(destination, 'IDRiD', relative_name(path, cfg.data.idridRoot)));
            end
        end
    end
end

function relative = relative_name(file, root)
    prefix = [char(root) filesep];
    assert(strncmpi(char(file), prefix, numel(prefix)), 'File is outside the expected folder.');
    relative = char(file);
    relative = relative(numel(prefix)+1:end);
end

function copy_one(source, destination)
    parent = fileparts(destination);
    if ~isfolder(parent)
        mkdir(parent);
    end
    [ok, message] = copyfile(source, destination);
    assert(ok, '%s', message);
end

function write_json_local(path, value)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot create export JSON file.');
    guard = onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end

function write_readme(path)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot create export readme.');
    guard = onCleanup(@()fclose(fid)); %#ok<NASGU>
    lines = { ...
        'NIMEQ EXISTING-RECORDS COLLECTION FOR REVIEW', ...
        '', ...
        'This export contains records of new workstation reconstruction experiments.', ...
        'It is a review collection, not a claim of original publication reproduction.', ...
        '', ...
        'code/current: current working code, documentation and saved local-validation logs.', ...
        'code/previous_*: other located code copies, kept separately for comparison.', ...
        'runs/d7c41: DR7 binary; runs/d7m41: DR7 five/seven class; runs/idw41: IDRiD.', ...
        'collection_metadata.json: actual saved budgets and checks on the exported copies.', ...
        'omitted_files.csv: files intentionally left in the original run folders.', ...
        'bundle_inventory.csv and BUNDLE_SHA256SUMS.txt: hashes of this collected evidence.', ...
        '', ...
        'Original status.json, run_identity.json and authored_code_sha256.csv are unchanged.', ...
        'A saved failed status may precede the separately recorded successful postprocessing checks.', ...
        'Original SHA256SUMS.txt files are historical inventories and can contain stale entries.', ...
        'The new bundle hash list describes the collected bytes; it does not rewrite run identities.', ...
        '', ...
        'Augmentation ancestry, case predictions, counts, metrics, search/training histories,', ...
        'figures, verification history, configuration.mat and input-quality reports are retained.', ...
        'Small original annotation workbooks/label CSVs are included when their saved paths exist.', ...
        'Source-image caches, augmented image pixels, model/checkpoint binaries and the two', ...
        'large raw-feature CSVs are omitted from runs and remain in the original folders.', ...
        'Preserved reference_inputs, if present in a code snapshot, are copied unchanged.', ...
        'configuration.mat retains exact MATLAB settings, including Inf values.', ...
        'Paths inside original records are preserved and may refer to the original computer.', ...
        '', ...
        'Export checks recompute final metrics and membership with source rehashing and', ...
        'deep-CV checking disabled. They do not rerun training or validate scientific accuracy.', ...
        'Only the exported copies receive new verification reports. Original records are unchanged.'};
    fprintf(fid, '%s\n', lines{:});
end

function write_inventory(root)
    files = dir(fullfile(root, '**', '*'));
    files = files(~[files.isdir]);
    relative = strings(numel(files), 1);
    bytes = zeros(numel(files), 1);
    sha256 = strings(numel(files), 1);
    for i = 1:numel(files)
        path = fullfile(files(i).folder, files(i).name);
        relative(i) = string(strrep(relative_name(path, root), '\', '/'));
        bytes(i) = files(i).bytes;
        sha256(i) = string(nimeq.hash_file(path));
        if mod(i, 250) == 0
            fprintf('Hashing exported files %d/%d\n', i, numel(files));
        end
    end
    inventory = sortrows(table(relative, bytes, sha256), 'relative');
    inventoryFile = fullfile(root, 'bundle_inventory.csv');
    writetable(inventory, inventoryFile);
    fid = fopen(fullfile(root, 'BUNDLE_SHA256SUMS.txt'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot create bundle checksum list.');
    guard = onCleanup(@()fclose(fid)); %#ok<NASGU>
    for i = 1:height(inventory)
        fprintf(fid, '%s  %s\n', char(inventory.sha256(i)), char(inventory.relative(i)));
    end
    fprintf(fid, '%s  bundle_inventory.csv\n', char(nimeq.hash_file(inventoryFile)));
end
