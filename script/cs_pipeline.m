folders = {};
file_spec = folders;
% file_spec = [ file_spec, '04242018_position_2' ];

shared_inputs = { 'files_containing', file_spec, 'overwrite', false };

%%

bfw.make_cs_sync_times( shared_inputs{:} );

%%  

bfw.make_cs_edfs( shared_inputs{:} );

%%

bfw.make_cs_task_events( shared_inputs{:} );