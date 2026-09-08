`timescale 1ns/1ps
module tb_rr_writer;
    localparam CH = 4, DW = 32, AW = 16, BEATS = 4;
    localparam NB = 12;                        // bursts, 3 times round the walk

    reg clk = 0, rst = 1, go = 0;
    always #2 clk = ~clk;                      // 250 MHz

    wire busy, done;
    wire [31:0] cycles;
    wire [CH-1:0]    awvalid, wvalid, wlast;
    wire [CH*AW-1:0] awaddr;
    wire [CH*DW-1:0] wdata;

    rr_writer #(.CH(CH), .DW(DW), .AW(AW), .BEATS(BEATS)) dut (
        .clk(clk), .rst(rst), .go(go), .n_burst(NB),
        .busy(busy), .done(done), .cycles(cycles),
        .awvalid(awvalid), .awaddr(awaddr),
        .wvalid(wvalid), .wdata(wdata), .wlast(wlast));

    // ---- waveform aids -------------------------------------------------
    // The buses are flattened for the port list; a viewer can only show that
    // as one wide hex value. Name the parts a reader needs to follow.
    wire [AW-1:0] ch0_addr = awaddr[0*AW +: AW];
    wire [DW-1:0] ch0_wdata  = wdata [0*DW +: DW];

    // Which channel was addressed last, as a number. It HOLDS between bursts
    // so the walk reads as a staircase rather than a row of spikes.
    reg [3:0]  ch_num;
    reg [15:0] burst_n;
    integer k;
    always @(posedge clk)
        if (rst) begin ch_num <= 0; burst_n <= 0; end
        else for (k = 0; k < CH; k = k + 1)
            if (awvalid[k]) begin ch_num <= k[3:0]; burst_n <= burst_n + 1; end

    initial begin
        if ($test$plusargs("fsdb")) begin
            $fsdbDumpfile("tb_rr_writer.fsdb");
            $fsdbDumpvars(0, tb_rr_writer);
        end
        repeat (4) @(posedge clk); rst <= 0;
        repeat (2) @(posedge clk);
        @(posedge clk) go <= 1; @(posedge clk) go <= 0;
        wait (done);
        $display("[PASS] %0d bursts in %0d cycles", NB, cycles);
        repeat (4) @(posedge clk);
        $finish;
    end
endmodule
