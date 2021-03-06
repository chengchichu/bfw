import shared_utils.io.fload;

conf = bfw.config.load();

event_p = bfw.get_intermediate_directory( 'events' );
unified_p = bfw.get_intermediate_directory( 'unified' );
bounds_p = bfw.get_intermediate_directory( 'bounds' );
sync_p = bfw.get_intermediate_directory( 'sync' );
spike_p = bfw.get_intermediate_directory( 'spikes' );
event_files = shared_utils.io.find( event_p, '.mat' );

first_event_file = fload( event_files{1} );
first_bounds_file = fload( fullfile(bounds_p, first_event_file.unified_filename) );
first_event_params = first_event_file.params;

save_plot_p = fullfile( conf.PATHS.data_root, 'plots' );

look_save_p = fullfile( save_plot_p, 'looking_behavior', datestr(now, 'mmddyy') );

event_param_str = sprintf( 'event_%s_%d', first_event_params.mutual_method, first_event_params.duration );
window_param_str = sprintf( 'window_%d_step_%d', first_bounds_file.window_size, first_bounds_file.step_size );
event_subdir = sprintf( '%s_%s', event_param_str, window_param_str );

look_save_p = fullfile( look_save_p, event_subdir );

shared_utils.io.require_dir( look_save_p );

cont = Container();
evt_info = Container();
all_event_lengths = Container();
all_event_distances = Container();
rasters = Container();

spike_map = containers.Map();

update_spikes = true;

look_back = -0.5;
look_ahead = 0.5;
psth_bin_size = 0.05;

fs = 1e3;

upper_distance_threshold = 1; % longest time allowed between events
lower_distance_threshold = 100 / 1e3;  % shortest time between events, ms

for i = 1:numel(event_files)

  fprintf( '\n %d of %d', i, numel(event_files) );
  
  events = fload( event_files{i} );
  unified = fload( fullfile(unified_p, events.unified_filename) );
  plex_file = unified.m1.plex_filename;
  
  sync_file = fullfile( sync_p, events.unified_filename );
  spike_file = fullfile( spike_p, events.unified_filename );
  
  if ( exist(sync_file, 'file') == 0 || exist(spike_file, 'file') == 0 )
    fprintf( '\n Missing sync or spike file for "%s".', events.unified_filename );
    continue;
  end
  
  sync = fload( sync_file );
  spikes = fload( spike_file );
  
  if ( ~spikes.is_link )
    spike_map( plex_file ) = spikes;
  elseif ( ~spike_map.isKey(plex_file) )
    spikes = fload( fullfile(spike_p, spikes.data_file) );
    spike_map( plex_file ) = spikes;
  else
    spikes = spike_map( plex_file );
  end
  
  %   convert spike times in plexon time (a) to matlab time (b)
  clock_a = sync.plex_sync(:, strcmp(sync.sync_key, 'plex'));
  clock_b = sync.plex_sync(:, strcmp(sync.sync_key, 'mat'));
  
  rois = events.roi_key.keys();
  monks = events.monk_key.keys();
  unit_indices = arrayfun( @(x) x, 1:numel(spikes.data), 'un', false );
  
  C = bfw.allcomb( {rois, monks, unit_indices} );
  C1 = bfw.allcomb( {rois, monks} );
  hell0 = 1
  %   first get event info
  
  for j = 1:size(C1, 1)
    roi = C1{j, 1};
    monk = C1{j, 2};
    row = events.roi_key( roi );
    col = events.monk_key( monk );
    
    evts = events.times{row, col};
%     evt_lengths = events.lengths{row, col}; % to seconds
    evt_lengths = events.durations{row, col};
    
    n_evts = numel( evts );
    
    evt_distances = diff( evts );
    median_evt_distance = median( evt_distances );
    min_evt_distance = min( evt_distances );
    max_evt_distance = max( evt_distances );
    dev_evt_distance = std( evt_distances );
    
    perc_above_threshold_distance = perc( evt_distances(:) >= upper_distance_threshold );
    perc_below_threshold_distance = perc( evt_distances(:) <= lower_distance_threshold );
    
    median_evt_length = median( evt_lengths );
    max_evt_length = max( evt_lengths );
    min_evt_length = min( evt_lengths );
    dev_evt_length = std( evt_lengths );
    
    if ( isempty(min_evt_distance) ), min_evt_distance = NaN; end
    if ( isempty(max_evt_distance) ), max_evt_distance = NaN; end
    if ( isempty(min_evt_length) ), min_evt_length = NaN; end
    if ( isempty(max_evt_length) ), max_evt_length = NaN; end
    
    labs = SparseLabels.create( ...
        'looks_to', roi ...
      , 'looks_by', monk ...
      , 'unified_filename', unified.m1.unified_filename ...
      , 'session_name', unified.m1.mat_directory_name ...
      , 'meas_type', 'undefined' ...
    );
    
    cont1 = Container( n_evts, labs );
    cont2 = Container( median_evt_distance, labs );
    cont3 = Container( max_evt_distance, labs );
    cont4 = Container( min_evt_distance, labs );
    cont5 = Container( dev_evt_distance, labs );
    cont6 = Container( perc_above_threshold_distance, labs );
    cont7 = Container( perc_below_threshold_distance, labs );
    
    conts = extend( cont1, cont2, cont3, cont4, cont5, cont6, cont7 );
    conts('meas_type') = { 'n_events', 'median_distance', 'max_distance' ...
      , 'min_distance', 'dev_distance' ...
      , 'perc_above_threshold_distance', 'perc_below_threshold_distance' };
    
    cont1 = Container( median_evt_length, labs );
    cont2 = Container( max_evt_length, labs );
    cont3 = Container( min_evt_length, labs );
    
    conts2 = extend( cont1, cont2, cont3 );
    conts2('meas_type') = { 'median_length', 'max_length', 'min_length' };
    
    evt_info = evt_info.extend( conts, conts2 );
    
    pairs = cont1.field_label_pairs();
    
    all_event_lengths = all_event_lengths.append( Container(evt_lengths(:), pairs{:}) );
    all_event_distances = all_event_distances.append( Container(evt_distances(:), pairs{:}) );
  end
  
  if ( ~update_spikes ), continue; end
  
  %   then get spike info
  
  N = size(C, 1);
%   N = 1;
  
  for j = 1:N
    roi = C{j, 1};
    monk = C{j, 2};
    unit_index = C{j, 3};
    
    row = events.roi_key(roi);
    col = events.monk_key(monk);
    
    unit = spikes.data(unit_index);
    
    unit_start = unit.start;
    unit_stop = unit.stop;
    spike_times = unit.times;
    channel_str = unit.channel_str;
    region = unit.region;
    unit_name = unit.name;
    unified_filename = spikes.unified_filename;
    mat_directory_name = unified.m1.mat_directory_name;    
    
    event_times = events.times{row, col};
    
    if ( isempty(event_times) || isempty(spike_times) ), continue; end
    
    if ( unit_start == -1 ), unit_start = spike_times(1); end
    if ( unit_stop == -1 ), unit_stop = spike_times(end); end
    
    within_time_bounds = spike_times >= unit_start & spike_times <= unit_stop;
    
    spike_times = spike_times(within_time_bounds);
    
    if ( isempty(spike_times) ), continue; end
    
    mat_spikes = bfw.clock_a_to_b( spike_times, clock_a, clock_b );
    
    %   discard events that occur before the first spike, or after the
    %   last spike
    event_times = event_times( event_times >= mat_spikes(1) & event_times <= mat_spikes(end) );
    
    if ( isempty(event_times) ), continue; end
    
    [psth, bint] = looplessPSTH( mat_spikes, event_times, look_back, look_ahead, psth_bin_size );
    raster = bfw.make_raster( mat_spikes, event_times, look_back, look_ahead, fs );
    
    n_events = numel( event_times );
    
    cont_ = Container( psth, ...
        'channel', channel_str ...
      , 'region', region ...
      , 'unit_name', unit_name ...
      , 'looks_to', roi ...
      , 'looks_by', monk ...
      , 'unified_filename', unified_filename ...
      , 'session_name', mat_directory_name ...
      , 'n_events', sprintf( 'n_events__%d', n_events ) ...
      );
    
    cont = cont.append( cont_ );
    
    unqs = cont_.field_label_pairs();
    
    rasters = rasters.append( Container(raster, unqs{:}) );
  end
end

if ( update_spikes )
  cont = cont.require_fields( 'unit_id' );
  [I, C] = cont.get_indices( {'channel', 'region', 'unit_name', 'session_name'} );
  for i = 1:numel(I)
    cont('unit_id', I{i}) = sprintf( 'unit__%d', i );
  end
  rasters = rasters.require_fields( 'unit_id' );
  for i = 1:size(C, 1)
    ind = rasters.where(C(i, :));
    rasters('unit_id', ind) = sprintf( 'unit__%d', i );
  end
end
hello = 1
%%  plot population response matrix

psth = cont;

pre_bin_t = -0.2;
post_bin_t = 0.2;

pre_ind = bint >= pre_bin_t & bint < 0;
post_ind = bint > 0 & bint <= post_bin_t;

psth_pre = set_data( psth, nanmean(psth.data(:, pre_ind), 2) );
psth_post = set_data( psth, nanmean(psth.data(:, post_ind), 2) );

psth_modulation = (psth_post.data - psth_pre.data) ./ (psth_post.data + psth_pre.data);

psth_modulation = abs( psth_modulation );

psth_modulation = set_data( psth_post, psth_modulation );

psth_modulation = psth_modulation.each1d( {'unit_id', 'looks_by', 'looks_to'}, @rowops.nanmean );

psth_modulation = psth_modulation({'m1', 'mutual'});

[I, C] = psth_modulation.get_indices( {'unit_id'} );

modulation_index = Container();

fig = figure(1); clf( fig );

x_range = 1;
y_range = 1;

colors = containers.Map();
colors( 'bla' ) = 'r';
colors( 'accg' ) = 'b';

res = Container();

legend_components = containers.Map();

for i = 1:numel(I)
  subset_ = psth_modulation(I{i});
  
  regs = subset_('region');
  
  reg = char( regs );
  
  current_color = colors( reg );
  
%   if ( i == 1 ), legend( gca, '-dynamiclegend' ); end
  legend( '-dynamiclegend' );
  
  for j = 1:numel(regs)
    subset = subset_(regs(j));
    
    ind_face = subset.where( 'face' );
    ind_eyes = subset.where( 'eyes' );
    ind_mut = subset.where( 'mutual' );
    ind_excl = subset.where( {'m1'} );

    if ( ~any(ind_face) || ~any(ind_eyes) || ~any(ind_mut) || ~any(ind_excl) )
      fprintf( '\n skipping "%s"', strjoin([regs{j}, C(i, :)], ', ') );
      continue;
    end

    face = subset.data(ind_face);
    eyes = subset.data(ind_eyes);
    mut = subset.data(ind_mut);
    excl = subset.data(ind_excl);

    eyes_over_face = (eyes-face) ./ (face + eyes);
    mut_over_excl = (mut-excl) ./ (mut + excl);

    x_coord = eyes_over_face * x_range;
    y_coord = mut_over_excl * y_range;
    
    pairs = field_label_pairs( one(subset) );
    
    res = res.append( Container([eyes_over_face, mut_over_excl], pairs{:}) );

    h = plot( x_coord, y_coord, sprintf('%so', current_color), 'MarkerFaceColor', current_color, 'markersize', 6 ); hold on;
    
    if ( ~legend_components.isKey(regs{j}) )
      legend_components(regs{j}) = h;
    end
  end
end

[I, C] = res.get_indices( 'region' );

corred = Container();

for i = 1:numel(I)
  reg = res(I{i});
  reg( any(isnan(reg.data), 2) ) = [];
  [r, p] = corr( reg.data(:, 1), reg.data(:, 2) );
  corred = corred.append( set_data(one(reg), [r, p]) );
end

% title( 'ACCg' );

hold on;
plot( [-1, 1], [0, 0], 'k-' );
plot( [0, 0], [-1, 1], 'k-' );

xlabel( 'eyes over face' );
ylabel( 'mutual over exclusive' );

ylim( [-1, 1] );
xlim( [-1, 1] );

axis( 'square' );

leg_keys = legend_components.keys();
leg_elements = gobjects( 1, numel(leg_keys) );

for i = 1:numel(leg_keys)
  leg_elements(i) = legend_components(leg_keys{i}); 
end

legend( leg_elements, leg_keys );

%   save
kind = 'population_matrix';
fname = strjoin( res.flat_uniques({'session_name'}), '_' );
fname = sprintf( 'population_matrix_%s', fname );
date_dir = datestr( now, 'mmddyy' );
save_plot_p = fullfile( conf.PATHS.data_root, 'plots', 'population_response' );
save_plot_p = fullfile( save_plot_p, date_dir, kind, event_subdir );
shared_utils.io.require_dir( save_plot_p );

shared_utils.plot.save_fig( gcf, fullfile(save_plot_p, fname), {'epsc', 'png', 'fig'} );

%%  plot histogram of event lengths

pl = ContainerPlotter();

panels_are = { 'looks_to', 'looks_by' };

figure(1); clf();

pl.hist( all_event_lengths, 500, [], panels_are );

% filename = sprintf( 'event_length_histogram_', filename );
filename = 'event_length_histogram';
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );

%%  plot histogram of event distances

pl = ContainerPlotter();

panels_are = { 'looks_to', 'looks_by' };

figure(1); clf();

pl.hist( all_event_distances, 500, [], panels_are );

% filename = sprintf( 'event_length_histogram_', filename );
filename = 'event_distance_histogram';
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );

%%  plot bar of event distances

pl = ContainerPlotter();

figure(1); clf(); colormap( 'default' );

plt = all_event_distances;

% pl.summary_function = @min;

plt('unified_filename') = 'a';
plt('session_name') = 'b';

panels_are = { 'unified_filename', 'session_name', 'meas_type' };
groups_are = { 'looks_to' };
x_is = 'looks_by';

pl.bar( plt, x_is, groups_are, panels_are );

filename = strjoin( plt.flat_uniques(plt.categories()), '_' );

meas_types = strjoin( plt('meas_type'), '_' );

filename = sprintf( 'event_distances_%s_%s', filename, meas_types );
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );


%%  event info

pl = ContainerPlotter();

pl.summary_function = @nanmean;
pl.error_function = @ContainerPlotter.nansem;

figure(1); clf(); colormap( 'default' );

plt = evt_info;

% plt = plt({'perc_below_threshold_distance'});
plt = plt({'median_length'});

plt('unified_filename') = 'a';
plt('session_name') = 'b';

panels_are = { 'unified_filename', 'session_name', 'meas_type' };
groups_are = { 'looks_to' };
x_is = 'looks_by';

pl.bar( plt, x_is, groups_are, panels_are );

filename = strjoin( plt.flat_uniques(plt.categories()), '_' );

meas_types = strjoin( plt('meas_type'), '_' );

filename = sprintf( 'event_length_%s_%s', filename, meas_types );
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );

%%  n events per session

pl = ContainerPlotter();
pl.summary_function = @nanmean;
pl.error_function = @ContainerPlotter.nansem;

figure(1); clf(); colormap( 'default' );

plt = evt_info;

plt = plt({'n_events'});
plt('unified_filename') = 'a';
plt('session_name') = 'b';

panels_are = { 'unified_filename', 'session_name', 'meas_type' };
groups_are = { 'looks_to' };
x_is = 'looks_by';

pl.bar( plt, x_is, groups_are, panels_are );

filename = strjoin( plt.flat_uniques(plt.categories()), '_' );

filename = sprintf( 'n_events_per_session_%s', filename );
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );

%%  n events per day

pl = ContainerPlotter();
pl.summary_function = @nanmean;
pl.error_function = @ContainerPlotter.nansem;

figure(1); clf(); colormap( 'default' );

plt = evt_info;

plt = plt({'n_events'});

plt = plt.each1d( {'session_name', 'meas_type', 'looks_to', 'looks_by'}, @rowops.sum );

plt('unified_filename') = 'a';
plt('session_name') = 'b';

panels_are = { 'session_name', 'meas_type' };
groups_are = { 'looks_to' };
x_is = 'looks_by';

pl.bar( plt, x_is, groups_are, panels_are );

filename = strjoin( plt.flat_uniques(plt.categories()), '_' );

filename = sprintf( 'n_events_per_day_%s', filename );
  
saveas( gcf, fullfile(look_save_p, [filename, '.eps']) );
saveas( gcf, fullfile(look_save_p, [filename, '.png']) );
%%

pl = ContainerPlotter();
pl.x = bint;
pl.vertical_lines_at = 0;
pl.add_ribbon = true;

figure(1); clf();

plt = cont;

plt = plt({'01162018', '01172018'});

plt = plt({'face', 'bla'});

plt.plot( pl, 'looks_to', 'looks_by' );

%%  per unit

date_dir = datestr( now, 'mmddyy' );

% plt = cont({'01162018', '01172018'});
plt = cont;

% plt = plt.replace( 'm1', 'zm1' );
% plt = plt.replace( 'm2', 'zm2' );

kind = 'per_unit';

save_plot_p = fullfile( conf.PATHS.data_root, 'plots', 'psth' );
save_plot_p = fullfile( save_plot_p, date_dir, kind );
save_plot_p = fullfile( save_plot_p, event_subdir );

shared_utils.io.require_dir( save_plot_p );

[I, C] = plt.get_indices( {'unit_id'} );

for i = 1:numel(I)
  subset = plt(I{i});
  
  pl.default();
  pl.x = bint;
  pl.vertical_lines_at = 0;
  pl.shape = [3, 2];
  pl.order_panels_by = { 'mutual', 'm1' };
  
  figure(1); clf();
  
%   subset.plot( pl, 'looks_to', {'looks_by', 'region', 'unit_id'} );
  h = subset.plot( pl, 'looks_to', {'looks_by', 'looks_to', 'region', 'unit_id'} );
  
  matching_raster = rasters(C(i, :));
  
  
  filename = strjoin( subset.flat_uniques({'region', 'looks_to', 'looks_by', 'unit_id'}), '_' );
  
  saveas( gcf, fullfile(save_plot_p, [filename, '.eps']) );
  saveas( gcf, fullfile(save_plot_p, [filename, '.png']) );
  
end

%%  per unit, overlay rasters

pl = ContainerPlotter();

date_dir = datestr( now, 'mmddyy' );

% plt = cont({'01162018', '01172018'});
% plt = cont;
plt = cont({'01162018', '01172018'});
plt = plt({'m1_leads_m2','m2_leads_m1'});

% plt = plt.replace( 'm1', 'zm1' );
% plt = plt.replace( 'm2', 'zm2' );

kind = 'per_unit_rasters';

save_plot_p = fullfile( conf.PATHS.data_root, 'plots', 'psth' );
save_plot_p = fullfile( save_plot_p, date_dir, kind, event_subdir );

shared_utils.io.require_dir( save_plot_p );

[I, C] = plt.get_indices( {'unit_id', 'looks_to', 'looks_by', 'region'} );

fig = figure(1);

for i = 185:numel(I)
  fprintf( '\n %d of %d', i, numel(I) );
  
  subset = plt(I{i});
  
  pl.default();
  pl.x = bint;
  pl.vertical_lines_at = 0;
%   pl.shape = [3, 2];
  pl.order_panels_by = { 'mutual', 'm1' };
  pl.add_legend = false;
  
  clf(fig);
  
%   h = subset.plot( pl, 'looks_to', {'looks_by', 'looks_to', 'region', 'unit_id'} );
  
  title_str = strjoin( flat_uniques(subset, {'looks_by', 'looks_to', 'region', 'unit_id'}), ' | ' );
  
  meaned_data = nanmean( subset.data, 1 );
  sem_data = ContainerPlotter.nansem( subset.data );
  
  matching_raster = rasters(C(i, :));
  
  y_lims = get( gca, 'ylim' );
  x_lims = get( gca, 'xlim' );
  
  min_x_lim = x_lims(1);
  max_x_lim = x_lims(2);
  max_y_lim = y_lims(2);
  min_y_lim = y_lims(1);
  
  min_y_lim = max_y_lim - (max_y_lim - min_y_lim) / 8;
  
  raster_data = matching_raster.data;
  
  for j = 1:size(raster_data, 1)
    for k = 1:size(raster_data, 2)
      perc_y = (j-1) / size(raster_data, 1);
      perc_x = (k-1) / size(raster_data, 2);
      x_coord = ((max_x_lim - min_x_lim) * perc_x) + min_x_lim;
      y_coord = ((max_y_lim - min_y_lim) * perc_y) + min_y_lim;
      if ( raster_data(j, k) )
        hold on;
        plot( x_coord, y_coord, 'k*', 'markersize', 1 );
      end
    end
  end
  
  filename = strjoin( subset.flat_uniques({'region', 'looks_to', 'looks_by', 'unit_id'}), '_' );
  
  shared_utils.plot.save_fig( gcf, fullfile(save_plot_p, filename), {'png', 'epsc', 'fig'}, true );
  
end


