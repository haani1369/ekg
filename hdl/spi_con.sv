`default_nettype none

module spi_con #(
  parameter DATA_WIDTH = 8,
  parameter DATA_CLK_PERIOD = 100
) (
  input wire clk_in,                      //system clock (100 MHz)
  input wire rst_in,                      //reset in signal
  input wire [DATA_WIDTH-1:0] data_in,    //data to send
  input wire trigger_in,                  //start a transaction
  output logic [DATA_WIDTH-1:0] data_out, //data received!
  output logic data_valid_out,            //high when output data is present.
  output logic chip_data_out,             //(COPI)
  input wire chip_data_in,                //(CIPO)
  output logic chip_clk_out,              //(DCLK)
  output logic chip_sel_out               //(CS)
);
  localparam TWICE_CLK_PERIOD = (DATA_CLK_PERIOD[0] == 1'b1)
    ? (DATA_CLK_PERIOD - 1)
    : DATA_CLK_PERIOD;
  localparam ACTUAL_CLK_PERIOD = TWICE_CLK_PERIOD / 2;
  localparam DATA_CLK_PERIOD_WIDTH = $clog2(ACTUAL_CLK_PERIOD);
  localparam COUNTER_WIDTH = $clog2(DATA_WIDTH);
  
  typedef enum {
    IDLE, START, TRANSMIT, COMPLETE
  } fsm_state;

  logic [DATA_CLK_PERIOD_WIDTH-1:0] cycle_number;
  logic [COUNTER_WIDTH-1:0] counter;

  logic [DATA_WIDTH-1:0] stored_data_in;

  fsm_state state;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      cycle_number <= 0;
      counter <= 0;
      state <= IDLE;

      data_out <= 0;
      data_valid_out <= 1'b0;
      chip_data_out <= 1'b0;
      chip_clk_out <= 1'b0;
      chip_sel_out <= 1'b1; // cs held high
    end else begin
      case (state)
        IDLE: begin
          data_valid_out <= 1'b0;
          chip_clk_out <= 1'b0;
          chip_sel_out <= 1'b1;

          state <= trigger_in? START : IDLE;
          stored_data_in <= data_in;
        end

        START: begin
          counter <= 'b0;
          cycle_number <= 'b0;

          chip_sel_out <= 1'b0; // signal starting transaction
          state <= TRANSMIT;
        end

        TRANSMIT: begin
          if (cycle_number == ACTUAL_CLK_PERIOD-1) begin
            cycle_number <= 'b0; // reset for next clock edge
            chip_clk_out <= ~chip_clk_out; // drive clock

            if (!chip_clk_out) begin // rising edge
              // receive data
              data_out <= {data_out[DATA_WIDTH-2:0], chip_data_in};
            end else begin // falling edge
              // send data
              chip_data_out <= stored_data_in[DATA_WIDTH-1];
              stored_data_in <= (stored_data_in << 1);

              counter <= counter + 1;
              state <= (counter == DATA_WIDTH-1)? COMPLETE : TRANSMIT; 
            end
          end else begin
            cycle_number <= cycle_number + 1;
          end
        end

        COMPLETE: begin
          data_valid_out <= 1'b1;
          chip_clk_out <= 1'b0;
          chip_sel_out <= 1'b1;
          state <= IDLE;
        end

        default: begin
          cycle_number <= 0;
          counter <= 0;
          state <= IDLE;

          data_out <= 0;
          data_valid_out <= 1'b0;
          chip_data_out <= 1'b0;
          chip_clk_out <= 1'b0;
          chip_sel_out <= 1'b1; // cs held high
        end
      endcase
    end
  end
endmodule
    
`default_nettype wire
