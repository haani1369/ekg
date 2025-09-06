`default_nettype none

module fir_filter # (
  parameter DATA_RESOLUTION = 8,
  parameter NUM_LEADS = 1
) (
  input wire clk_in,
  input wire rst_in,
  input wire signed [NUM_LEADS-1:0] [DATA_RESOLUTION-1:0] signed_data_in,
  input wire data_valid_in,
  output logic signed [NUM_LEADS-1:0] [DATA_RESOLUTION-1:0] signed_data_out,
  output logic data_valid_out
);
  localparam KERNEL_SIZE = 20;
  localparam EXTRA_PIPELINING_DELAY = 2;

  // pipelining stuff
  logic data_valid_out_pipe [EXTRA_PIPELINING_DELAY-1:0];
  always_ff @(posedge clk_in) begin
    for (int i = 1; i < EXTRA_PIPELINING_DELAY; i=i+1) begin
      data_valid_out_pipe[i] <= data_valid_out_pipe[i-1];
    end

    data_valid_out <= data_valid_out_pipe[EXTRA_PIPELINING_DELAY-1];
  end

  // actual logic
  logic signed [KERNEL_SIZE-1:0] [DATA_RESOLUTION-1:0] signed_kernel;
  logic signed [DATA_RESOLUTION-1:0] signed_kernel_shift;
  logic signed [KERNEL_SIZE-1:0] [NUM_LEADS-1:0] [DATA_RESOLUTION-1:0] signed_data_cache;

  logic signed [KERNEL_SIZE-1:0] [NUM_LEADS-1:0] [2*DATA_RESOLUTION-1:0] signed_multiply_results;
  logic signed [NUM_LEADS-1:0] [2*DATA_RESOLUTION-1:0] signed_add_result;

  // Simple moving average filter
  always_comb begin
    for (int i = 0; i < KERNEL_SIZE; i=i+1) begin
      signed_kernel[i] = $signed(1);
    end
    signed_kernel_shift = $signed(13);
  end

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      for (int i = 0; i < KERNEL_SIZE; i=i+1) begin
        signed_data_cache[i] <= 0;
        signed_multiply_results[i] <= 0;
        signed_add_result <= 0;
      end

       data_valid_out_pipe[0] <= 1'b0;
    end else if (data_valid_in) begin
      // store incoming data
      for (int i = 1; i < KERNEL_SIZE; i=i+1) begin
        signed_data_cache[i] <= signed_data_cache[i-1];
      end
      signed_data_cache[0] <= $signed(signed_data_in);

      // multiply
      for (int i = 0; i < KERNEL_SIZE; i=i+1) begin
        signed_multiply_results[i] <= $signed(
          signed_data_cache[i] * signed_kernel
        );
      end

      // add
      signed_add_result = $signed(
        signed_multiply_results[0]
        + signed_multiply_results[1]
        + signed_multiply_results[2]
        + signed_multiply_results[3]
        + signed_multiply_results[4]
        + signed_multiply_results[5]
        + signed_multiply_results[6]
        + signed_multiply_results[7]
        + signed_multiply_results[8]
        + signed_multiply_results[9]
        + signed_multiply_results[10]
        + signed_multiply_results[11]
        + signed_multiply_results[12]
        + signed_multiply_results[13]
        + signed_multiply_results[14]
        + signed_multiply_results[15]
        + signed_multiply_results[16]
        + signed_multiply_results[17]
        + signed_multiply_results[18]
        + signed_multiply_results[19]
      );

      data_valid_out_pipe[0] <= 1'b1;
    end else begin
      data_valid_out_pipe[0] <= 1'b0;
    end
  end


  logic signed [NUM_LEADS-1:0] [2*DATA_RESOLUTION-1:0] signed_shift_result;
  always_comb begin
    signed_shift_result = $signed(
      signed_add_result >>> signed_kernel_shift
    );

    signed_data_out = $signed(
      {
        signed_shift_result[0][2*DATA_RESOLUTION-1],
        signed_shift_result[0][DATA_RESOLUTION-2:0]
      }
    );
  end


endmodule

`default_nettype wire