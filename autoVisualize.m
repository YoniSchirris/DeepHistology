% JN Kather 2018-2020
% This is part of the DeepHistology repository
% License: see separate LICENSE file 
% 
% documentation for this function:
% this is the main function to visualize classification
% performance results (loaded from the dump folder of an experiment)

function autoVisualize(varargin)

addpath(genpath('./subroutines/'));      % add dependencies
iPrs = getDefaultInputParser(varargin);  % get input parser, define default values
cnst = loadExperiment(iPrs.Results.experiment); % load experiment from JSON
cnst.skipLoadingBlocks = true; % never load tiles for visualization
disp('-- starting VISUALIZE job with these input (or default) settings:');
dispAllFields(iPrs.Results);
cnst = copyfields(cnst,iPrs.Results,fieldnames(iPrs.Results)); % apply input
[cnst,~] = initializeDeepImagePipeline(cnst);  % initialize

% load results file
allfiles = dir([cnst.folderName.Dump,'/*lastResult*',cnst.saveFormat,'.mat']);
sq = @(varargin) varargin';
allnames = sq(allfiles.name);

% additional hard-coded settings, do not change
cnst.axTicks = 0:0.2:1;     % primary axis tick labels for ROC curves
cnst.axTicksFine = 0:0.1:1; % secondary axis tick labels for ROC curves
cnst.scaleYprerec = false; % scale y axis of pre rec curve, default false
cnst.plotSpec = false; % display specificity at fixed sens levels
cnst.firstAsLargePlot = false; % plot first ROC curve as large plot
cnst.plotGoldStandardMSI = false; %plot the literature Gold standard
cnst.doPlotHistogram = true; % plot tiles per patient as histogram if tiles are plotted
count = 1;
collectSparsePatients = []; % preallocate
% only process those names that are defined in the experiment file

if cnst.onlyExplicitTargets
    disp('--- visualizing only explicit targets');
    allnames(~contains(allnames,cnst.allTargets)) = [];
end

for currE = allnames' 

disp(['attempting to load ',char(currE)]);
    try
        load(fullfile(cnst.folderName.Dump,char(currE)))
    catch
        warning('file corrupt');
        continue
    end
disp(['--- loaded ',char(currE)]);

% only use multiple experiment results
disp(['displaying result for ',char(currE)]);

    if ~isempty(resultCollection)
        if isa(resultCollection,'cell') % legacy compatibility
            warning('detected legacy result collection... will use only first entry');
            res = resultCollection{1};
            clear resultCollection
            resultCollection = res;
        end
        currTarget = resultCollection.cnst.annotation.targetCol;
        disp([newline,'*** feature: ',currTarget,' ***',newline]);
        if ~isfield(resultCollection.cnst,'modelTemplate')
            resultCollection.cnst.modelTemplate = 'NA';
        end

        % plot ROC curves
        if cnst.doPlot && ~isempty(resultCollection.patientStats)
           resultCollection = plotROCcurves(resultCollection,cnst,currE);
        end
            
        % extract performance and save to results
        if ~isempty(resultCollection.patientStats)
    	res = parseStatistics(resultCollection);
        
        allVars = res.outT.Properties.VariableNames;
        for numRow = 1:size(res.outT,1)
            summary.count(count) = count;
            summary.project{count} = cnst.ProjectName;
            summary.varN{count} = res.varN;
            summary.proj{count} = res.proj;
            summary.filterBlocks{count} = res.filterBlocks; 
            for numVar = 1:numel(allVars)
                if iscell(res.outT.(allVars{numVar})(numRow))
                    summary.(allVars{numVar}){count} = res.outT.(allVars{numVar}){numRow};
                else
                    summary.(allVars{numVar}){count} = res.outT.(allVars{numVar})(numRow);
                end
            end
            
        % extract hyperaparameters and save to results
        summary.blockResizeMethod{count} = resultCollection.cnst.blocks.resizeMethod;
        try
        summary.aggregateMode{count} = resultCollection.cnst.aggregateMode;
        catch
            disp('legacy aggregateMode');
            summary.aggregateMode{count} = {'legacy'};
        end
        summary.MaxEpochs(count) = resultCollection.hyperprm.MaxEpochs;
        
        try   % v7
            summary.maxBlockNum(count) = resultCollection.cnst.maxBlockNum;
        catch % legacy v6
            disp('legacy maxBlockNum');
            summary.maxBlockNum(count) = resultCollection.cnst.blocks.maxBlockNum;   
        end
        
        summary.hotLayers(count) = copyIsField(resultCollection.hyperprm,'hotLayers',NaN);
        summary.hyper{count} = copyIsField(resultCollection.cnst,'hyper','N/A');
        summary.foldxval{count} = copyIsField(resultCollection.cnst,'foldxval',0);
        
        summary.learningRate(count) = resultCollection.hyperprm.InitialLearnRate;
        summary.modelTemplate{count} = resultCollection.cnst.modelTemplate;       
        summary.totalTime(count) = resultCollection.totalTime;
        summary.experimentID{count} = char(currE);      
        summary.nPatsTotal{count} = sum(res.outT.nPat);
    
        count = count+1;
        end   

        % optional: export CSV table with tile-level (block-level) predictions
        if cnst.exportBlockPred && isfield(resultCollection,'blockStats')
            blockNames = resultCollection.blockStats.BlockNames;
            allScores = resultCollection.blockStats.Scores;
            blockOutTable = [table(blockNames),array2table(allScores)];
            blockOutTable.Properties.VariableNames = [{'blockName'},fieldnames(resultCollection.patientStats.rawData.predictions)'];
            writetable(blockOutTable,...
                fullfile(cnst.folderName.Dump,[char(currE),'-',currTarget,'-blockLevelPredictions.csv']),...
                'Delimiter',';');
        end
        
            % optional: export the highest scoring tiles
            if isfield(cnst,'exportTopTiles') && (cnst.exportTopTiles > 0) && ...
                    anyAUC(resultCollection,cnst.plotAUCthreshold)
                [dcollect,sparsePatients] = getTopTiles(resultCollection,cnst,currTarget);
                drawnow
                if cnst.doPrint
                    writeTopTiles(dcollect,cnst,currE);
                end
                collectSparsePatients = [collectSparsePatients,sparsePatients];
            end
        else
            warning('empty patient stats... skip');
        end
         
    end
    
      
clear resultCollection res
disp('============================================================');

end
                
% summarize results, perform Benjamini-Hochberg FDR correction
if isfield(summary,'pVal')
    summary.fdrPval = mafdr(cell2mat(summary.pVal),'BHFDR',true);
else
    summary.fdrPval = [];
end

myT = struct2table(transposeStruct(summary)) %#ok
writetable(myT,['./output_tables/',...
     cnst.codename,'_',strrep(char(datetime),':','-'),'_lastTable.xlsx']);

 if cnst.debugMode
    disp('-- sparse patients for review:');
    disp(unique(collectSparsePatients));
 end
 
end
