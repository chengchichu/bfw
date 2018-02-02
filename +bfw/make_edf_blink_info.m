function make_edf_blink_info(varargin)

defaults = struct();
defaults.files = [];
defaults.files_containing = [];

params = bfw.parsestruct( defaults, varargin );

edf_p = bfw.get_intermediate_directory( 'edf' );

save_p = bfw.get_intermediate_directory( 'blinks' );

shared_utils.io.require_dir( save_p );

edfs = bfw.require_intermediate_mats( params.files, edf_p, params.files_containing );

for i = 1:numel(edfs)
  fprintf( '\n %d of %d', i, numel(edfs) );
  
  edf = shared_utils.io.fload( edfs{i} );
  
  fields = fieldnames( edf );
  
  unified_filename = edf.(fields{1}).unified_filename;
  
  blink_info = struct();
  
  for j = 1:numel(fields)
    c_edf = edf.(fields{j}).edf;
    
    s_blinks = c_edf.Events.Eblink.start;
    e_blinks = c_edf.Events.Eblink.end;
    
    blink_info.(fields{j}).starts = s_blinks;
    blink_info.(fields{j}).ends = e_blinks;
    blink_info.(fields{j}).durations = e_blinks - s_blinks;
    
    blink_info.(fields{j}).unified_filename = edf.(fields{j}).unified_filename;
  end
  
  filename = fullfile( save_p, unified_filename );
  
  save( filename, 'blink_info' );
end