`default_nettype none

module top_level (
  input wire clk_100mhz,

  input wire [3:0] btn,
  input wire [15:0] sw,
  output logic [2:0] rgb0,
  output logic [2:0] rgb1,
  output logic [15:0] led,

  output logic dclk,
  input wire cipo,
  output logic copi,
  output logic cs,

  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock
);

  // region /* PARAMETERS */

  //GLOBALS
  parameter ELECTRODES_USED = 2; // corresponds to channels used
  parameter NUM_LEADS = ELECTRODES_USED - 1;

  // ADC/SPI
  localparam CHANNEL_SELECT_WIDTH = 3; // MCP3008 supports 7 channels
  localparam ADC_DATA_WIDTH = 17; // MCP3008 datasheet
  localparam ADC_DATA_CLK_PERIOD = 50;
  localparam ADC_READ_PERIOD = 100_000;
  localparam ADC_READ_TIMER_WIDTH = $clog2(ADC_READ_PERIOD);
  // data
  localparam CLEAN_ADC_READ_DATA_START_INDEX = 1;
  localparam CLEAN_ADC_READ_DATA_END_INDEX = 10;
  localparam CLEAN_ADC_READ_DATA_WIDTH = (
    CLEAN_ADC_READ_DATA_END_INDEX - CLEAN_ADC_READ_DATA_START_INDEX + 1
  );
  localparam ACTUAL_DATA_RESOLUTION = CLEAN_ADC_READ_DATA_WIDTH + 1;
  // something...
  localparam RA_ELECTRODE_CHANNEL = 0;
  localparam LA_ELECTRODE_CHANNEL = 1;

  // endregion /* PARAMETERS */


  // region /* LOGIC DEFINITIONS */
  
  // FPGA
  logic sys_rst;
  assign sys_rst = btn[0];

  // region HDMI
  logic clk_pixel, clk_5x; //clock lines
  logic locked; //locked signal (we'll leave unused but still hook it up)

  //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
    .reset(0),
    .locked(locked),
    .clk_ref(clk_100mhz),
    .clk_pixel(clk_pixel),
    .clk_tmds(clk_5x)
  );

  logic [10:0] hcount; //hcount of system!
  logic [9:0] vcount; //vcount of system!
  logic hor_sync; //horizontal sync signal
  logic vert_sync; //vertical sync signal
  logic active_draw; //ative draw! 1 when in drawing region.0 in blanking/sync
  logic new_frame; //one cycle active indicator of new frame of info!
  logic [5:0] frame_count; //0 to 59 then rollover frame counter
 
  //written by you previously! (make sure you include in your hdl)
  //default instantiation so making signals for 720p
  video_sig_gen mvg(
    .pixel_clk_in(clk_pixel),
    .rst_in(sys_rst),
    .hcount_out(hcount),
    .vcount_out(vcount),
    .vs_out(vert_sync),
    .hs_out(hor_sync),
    .ad_out(active_draw),
    .nf_out(new_frame),
    .fc_out(frame_count)
  );

  logic [7:0] red, blue, green;

  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic tmds_signal [2:0]; //output of each TMDS serializer!
 
  //three tmds_encoders (blue, green, red)
  tmds_encoder tmds_red(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(red),
    .control_in(2'b0),
    .ve_in(active_draw),
    .tmds_out(tmds_10b[2])
  );

  tmds_encoder tmds_green(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(green),
    .control_in(2'b0),
    .ve_in(active_draw),
    .tmds_out(tmds_10b[1])
  );

  tmds_encoder tmds_blue(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(blue),
    .control_in({vert_sync, hor_sync}),
    .ve_in(active_draw),
    .tmds_out(tmds_10b[0])
  );
 
  //three tmds_serializers (blue, green, red):
  tmds_serializer red_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
    .tmds_in(tmds_10b[2]),
    .tmds_out(tmds_signal[2])
  );
 
  tmds_serializer green_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
    .tmds_in(tmds_10b[1]),
    .tmds_out(tmds_signal[1])
  );
 
  tmds_serializer blue_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
    .tmds_in(tmds_10b[0]),
    .tmds_out(tmds_signal[0])
  );
 
  //output buffers generating differential signals:
  //three for the r,g,b signals and one that is at the pixel clock rate
  //the HDMI receivers use recover logic coupled with the control signals asserted
  //during blanking and sync periods to synchronize their faster bit clocks off
  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

  // endregion HDMI

  // region SPI
  logic spi_trigger; 
  logic [ADC_DATA_WIDTH-1:0] spi_write_data;
  logic spi_read_data_valid;
  logic [ADC_DATA_WIDTH-1:0] spi_read_data;

  logic [CLEAN_ADC_READ_DATA_WIDTH-1:0] clean_spi_data_read;
  logic clean_spi_read_data_valid;

  spi_con #(
    .DATA_WIDTH(ADC_DATA_WIDTH),
    .DATA_CLK_PERIOD(ADC_DATA_CLK_PERIOD)
  ) my_spi_con (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),

    .chip_data_out(copi),
    .chip_data_in(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs),

    .trigger_in(spi_trigger),
    .data_in(spi_write_data),
    .data_valid_out(spi_read_data_valid),
    .data_out(spi_read_data)
  );

  // endregion

  // region addressing
  logic [ADC_READ_TIMER_WIDTH-1:0] adc_timer_count;
  logic counter_dummy;
  assign counter_dummy = 1'b1;
  evt_counter # (
    .MAX_COUNT(ADC_READ_PERIOD),
    .WIDTH(ADC_READ_TIMER_WIDTH)
  ) timer_counter_evt_counter (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .evt_in(counter_dummy), // just constantly count
    .count_out(adc_timer_count)
  );

  logic [CHANNEL_SELECT_WIDTH-1:0] channel_select;
  evt_counter # (
    .MAX_COUNT(ELECTRODES_USED+1),
    .WIDTH(CHANNEL_SELECT_WIDTH)
  ) channel_select_evt_counter (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .evt_in(spi_trigger),
    .count_out(channel_select)
  );

  // endregion addressing

  // region electrode lead registers (signed?)

  // takes in the clean SPI data. This data is marked as signed but only
  // represents the post-offset-but-pre-calculation stuff... the top bit is
  // going to be manually marked as 0 since it's all positive data.
  // EVERY DOWNSTREAM CALCULATION NEEDS TO BE SIGNED since that's what makes
  // sense physically
  logic signed [ACTUAL_DATA_RESOLUTION-1:0] ra_electrode_raw;
  logic signed [ACTUAL_DATA_RESOLUTION-1:0] la_electrode_raw;

  // signals that each electrode has been sampled from once since the previous
  // complete sample. This marks the point at which electrode leads should be
  // calculated.
  // single-cycle high in that case.
  logic trigger_sample_complete; 

  // the electrode difference leads. calculated when `trigger_sample_complete`
  // goes high. uses the raw electrode data.
  logic signed [ACTUAL_DATA_RESOLUTION-1:0] lead_I_raw;

  // signal downstream that data is ready to be read from. single-cycle high
  // since each lead is calculated in the same cycle.
  logic valid_leads_out;

  // endregion electrode leads

  // endregion /* LOGIC DEFINITIONS */


  // region /* ACTUAL STUFF */

  always_comb begin // fpga stuff
    sys_rst = btn[0];
  
    rgb0 = 1'b0;
    rgb1 = 1'b0;
  end // end fpga stuff

  always_comb begin // adc spi stuff
    spi_trigger = (adc_timer_count == 0);  // Only trigger new transactions periodically
    spi_write_data = {2'b11, channel_select, 12'b0}; // bottom 12 bits are don't care (from datasheet)
    clean_spi_data_read = spi_read_data[
      CLEAN_ADC_READ_DATA_END_INDEX:CLEAN_ADC_READ_DATA_START_INDEX
    ];
    clean_spi_read_data_valid = spi_read_data_valid;
  end // end adc spi stuff

  // assign trigger_sample_complete = clean_spi_read_data_valid;
  assign trigger_sample_complete = ( // just finished reading last channel
    channel_select == ELECTRODES_USED-1
    && clean_spi_read_data_valid
  );
  always_ff @(posedge clk_pixel) begin // do stuff with data read
    if (sys_rst) begin
      ra_electrode_raw <= 0;
      la_electrode_raw <= 0;
    end else if (clean_spi_read_data_valid) begin
      // record data
      case (channel_select)
        RA_ELECTRODE_CHANNEL: begin
          ra_electrode_raw <= $signed({1'b0, clean_spi_data_read});
        end
        LA_ELECTRODE_CHANNEL: begin
          la_electrode_raw <= $signed({1'b0, clean_spi_data_read});
        end
        default: begin
          // Keep existing values
        end
      endcase

      // calculate electrodes
      if (trigger_sample_complete) begin
        lead_I_raw <= $signed(
          // la_electrode_raw - 0
          // 0 - ra_electrode_raw
          la_electrode_raw - ra_electrode_raw
        );

        valid_leads_out <= 1'b1;
      end else begin
        valid_leads_out <= 1'b0;
      end
    end else begin
      valid_leads_out <= 1'b0;
    end
  end // end record data

  logic signed [NUM_LEADS-1:0] [ACTUAL_DATA_RESOLUTION-1:0] packed_signed_raw_leads = {lead_I_raw};

  logic signed [NUM_LEADS-1:0] [ACTUAL_DATA_RESOLUTION-1:0] packed_signed_filtered_leads;
  logic filter_data_valid;

  // antialias FIR filter
  fir_filter # (
    .DATA_RESOLUTION(ACTUAL_DATA_RESOLUTION),
    .NUM_LEADS(NUM_LEADS)
  ) my_fir_filter (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .signed_data_in(packed_signed_raw_leads),
    .data_valid_in(valid_leads_out),
    .signed_data_out(packed_signed_filtered_leads),
    .data_valid_out(filter_data_valid)
  );

  scrolling_graph # (
    .DATA_RESOLUTION(ACTUAL_DATA_RESOLUTION),
    .SCREEN_WIDTH(1280),
    .SCREEN_HEIGHT(720)
  ) my_scrolling_graph (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),

    .hcount_in(hcount),
    .vcount_in(vcount),
    .data_valid_in(filter_data_valid),
    .data_in(packed_signed_filtered_leads[0]),

    .pixel_valid_out(),
    .pixel_out({red, green, blue})
    // .pixel_out()
  );

  // endregion /* ACTUAL STUFF */

  assign led = packed_signed_filtered_leads[0];

endmodule // end top_level

`default_nettype wire
