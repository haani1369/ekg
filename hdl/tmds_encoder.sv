// `timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module tmds_encoder(
  input wire clk_in,
  input wire rst_in,
  input wire [7:0] data_in,  // video data (red, green or blue)
  input wire [1:0] control_in, //for blue set to {vs,hs}, else will be 0
  input wire ve_in,  // video data enable, to choose between control or video signal
  output logic [9:0] tmds_out
);
 
    logic [8:0] q_m;
    logic [2:0] q_m_one_count;

    count_ones my_count_ones(
        .number_in(q_m[7:0]),
        .count_ones_out(q_m_one_count)
    );
    
    tm_choice mtm(
        .data_in(data_in),
        .qm_out(q_m)
    );

    logic [4:0] tally;
 
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            tally <= 5'b0;
            tmds_out <= 10'b0;
        end else if (ve_in) begin
            if ((tally == 0) || (q_m_one_count == 4)) begin
                tmds_out[9] <= ~q_m[8];
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= (q_m[8])? q_m[7:0] : ~q_m[7:0];

                if (q_m[8] == 1'b1) begin
                    tally <= tally + (2 * q_m_one_count - 8);
                end else begin
                    tally <= tally + (8 - 2 * q_m_one_count);
                end
            end else if (
                    ((tally[4] == 1'b0) && (q_m_one_count > 4))
                    || ((tally[4] == 1'b1) && (q_m_one_count < 4))
            ) begin
                tmds_out[9] <= 1'b1;
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= ~q_m[7:0];
                tally <= tally + (2 * q_m[8]) + (8 - 2 * q_m_one_count);
            end else begin
                tmds_out[9] <= 1'b0;
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= q_m[7:0];
                tally <= tally - (2 * ~(q_m[8])) + (2 * q_m_one_count - 8);
            end
        end else begin
            case (control_in)
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
            endcase
        end
    end
 
endmodule
 
`default_nettype wire