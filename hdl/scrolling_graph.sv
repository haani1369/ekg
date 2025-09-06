`default_nettype none

module scrolling_graph #(
  parameter SCREEN_WIDTH = 1280,
  parameter SCREEN_HEIGHT = 720,
  parameter DATA_RESOLUTION = 8
) (
  input wire clk_in, // must be the HDMI clock
  input wire rst_in,

  input wire [$clog2(SCREEN_WIDTH)-1:0] hcount_in,
  input wire [$clog2(SCREEN_HEIGHT)-1:0] vcount_in,
  input wire data_valid_in,
  input wire signed [DATA_RESOLUTION-1:0] data_in,

  output logic pixel_valid_out,
  output logic [23:0] pixel_out
);
  localparam Y_AXIS = SCREEN_HEIGHT / 2;
  localparam HCOUNT_WIDTH = $clog2(SCREEN_WIDTH);
  localparam VCOUNT_WIDTH = $clog2(SCREEN_HEIGHT);
  localparam EXTRA_PIPELINING_DELAY = 1;

  // pipelining stuff
  logic pixel_valid_out_pipe [EXTRA_PIPELINING_DELAY-1:0];
  always_ff @(posedge clk_in) begin
    for (int i = 1; i < EXTRA_PIPELINING_DELAY; i=i+1) begin
      pixel_valid_out_pipe[i] <= pixel_valid_out_pipe[i-1];
    end

    pixel_valid_out <= pixel_valid_out_pipe[EXTRA_PIPELINING_DELAY-1];
  end

  // actual logic

  logic [HCOUNT_WIDTH-1:0] data_write_address;
  evt_counter #(
    .MAX_COUNT(SCREEN_WIDTH),
    .WIDTH(HCOUNT_WIDTH)
  ) hcount_counter (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .evt_in(data_valid_in),
    .count_out(data_write_address)
  );

  logic signed [DATA_RESOLUTION-1:0] signed_ram_data_read;
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(DATA_RESOLUTION),
    .RAM_DEPTH(SCREEN_WIDTH),
    .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) ram (
    // read from this port
    .clka(clk_in),
    .rsta(1'b0),
    .ena(1'b1),
    .wea(1'b0),
    .regcea(1'b1),
    .addra(hcount_in), // read address based on the hcount
    .dina(),
    .douta(signed_ram_data_read), // read SIGNED data to display
    
    // write to this port
    .clkb(clk_in),
    .rstb(1'b0),
    .enb(1'b1),
    .web(data_valid_in),  // Only write when data is valid
    .regceb(1'b0),
    .addrb(data_write_address), // write address based on hcount 
    .dinb(data_in),    // Write actual signed data
    .doutb()
  );

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      pixel_valid_out_pipe[0] <= 0;
      pixel_out <= 0;
    end else begin
      if (vcount_in == Y_AXIS) begin
        pixel_out <= 24'hFF_FF_FF;
      end else if (signed_ram_data_read[DATA_RESOLUTION-1] == 0) begin // positive
        if ($signed(Y_AXIS - vcount_in) > $signed(0) && 
            $signed(Y_AXIS - vcount_in) <= $signed(signed_ram_data_read)) begin
          pixel_out <= 24'h00_00_FF;
        end else begin
          pixel_out <= 0;
        end
      end else begin // negative
        // pixel_out <= 0;
        if ($signed(Y_AXIS - vcount_in) < $signed(0) && 
            $signed(Y_AXIS - vcount_in) >= $signed(signed_ram_data_read)) begin
          pixel_out <= 24'h00_00_FF;
        end else begin
          pixel_out <= 0;
        end
      end

      pixel_valid_out_pipe[0] <= 1'b1;
    end
  end

endmodule

`default_nettype wire
