folders = { '02082018', '02092018' };
file_spec = folders;

shared_inputs = { 'files_containing', file_spec, 'overwrite', false };

%%  unified

bfw.make_unified( folders );

%%  sync times

bfw.make_sync_times( shared_inputs{:} );

%%  edfs

bfw.make_edfs( shared_inputs{:} );

%%  blink info

bfw.make_edf_blink_info( shared_inputs{:} );

%%  aligned

bfw.make_edf_aligned( shared_inputs{:} );

%%  rois

bfw.make_rois( shared_inputs{:} );

%%  bounds

bfw.make_bounds( shared_inputs{:} ...
  , 'window_size', 500 ...
  , 'step_size', 10 ...
  , 'remove_blink_nans', true ...
);

%   separate eyes from face
bfw.adjust.separate_eyes_from_face( shared_inputs{:} );

%%  events

bfw.make_events( shared_inputs{:} ...
  , 'duration', 10 ...
);

%   classify events as m1 leading m2, vs. m2 leading m1
bfw.adjust.add_m_ordering( shared_inputs{:} ...g
  , 'max_lag', 2 ...
);

%   convert to plexon time
bfw.adjust.events_to_plex_time( shared_inputs{:} );

%   concatenate events within day
bfw.make_events_per_day( shared_inputs{:} );

%%  spikes

% bfw.make_spikes( shared_inputs{:} );
bfw.make_ms_spikes( shared_inputs{:} );

%%  event aligned spikes

bfw.make_aligned_spikes( shared_inputs{:} ...
  , 'psth_bin_size', 0.01 ...
  );

%%  lfp

bfw.make_lfp( shared_inputs{:} );

%%  modulation type

bfw.make_modulation_type( shared_inputs{:} ...
  , 'psth_bin_size', 0.01 ...
  , 'look_back', -0.5 ...
  , 'look_ahead', 0.5 ...
  , 'window_pre', [-0.3, 0] ...
  , 'window_post', [0, 0.3] ...
);