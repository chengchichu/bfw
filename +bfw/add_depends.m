function add_depends(conf)

%   ADD_DEPENDS -- Add paths to dependencies as defined in the config file.
%
%     IN:
%       - `conf` (config_file) |OPTIONAL|

if ( nargin < 1 ), conf = bfw.config.load(); end

repo = conf.PATHS.repositories;
depends = conf.DEPENDS.repositories;

for i = 1:numel(depends)
  addpath( genpath(fullfile(repo, depends{i})) );
end

end