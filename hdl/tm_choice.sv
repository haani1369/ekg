`default_nettype none

module tm_choice (
    input wire [7:0] data_in,
    output logic [8:0] qm_out
    );

    integer i;
    logic [2:0] number_of_ones;

    count_ones my_count_ones(
        .number_in(data_in),
        .count_ones_out(number_of_ones)
    );

    always_comb begin
        qm_out[0] = data_in[0];

        if ((number_of_ones > 4) || ((number_of_ones == 4) && data_in[0] == 0)) begin
            for (i = 1; i < 8; i = i+1) begin
                qm_out[i] = ~(qm_out[i-1] ^ data_in[i]); // XNORs
            end

            qm_out[8] = 1'b0;
        end else begin
            for (i = 1; i < 8; i = i+1) begin
                qm_out[i] = (qm_out[i-1] ^ data_in[i]); // XORs
            end

            qm_out[8] = 1'b1;
        end
    end

endmodule //end tm_choice

`default_nettype wire