`default_nettype none

module count_ones #(parameter NUMBER_WIDTH = 8, parameter COUNT_WIDTH = 3) (
    input wire [NUMBER_WIDTH-1:0] number_in,
    output logic [COUNT_WIDTH-1:0] count_ones_out
);
    integer i;

    always_comb begin
        count_ones_out = 0;

        for (i = 0; i < NUMBER_WIDTH; i++) begin
            if (number_in[i]) begin
                count_ones_out = count_ones_out + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire