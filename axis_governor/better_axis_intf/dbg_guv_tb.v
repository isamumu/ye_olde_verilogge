`timescale 1ns / 1ps

/*
dbg_guv_tb.v

A testbench for the AXIS governor controller.

In case you're wondering, no, I don't painstakingly write everything in my 
testbenches by hand. I mostly copy and paste and use Geany's regex find/replace 
tool.

For example,

Find: 
    .* (\w+)\,

Replace:
    \t\t\.\1\(\1\)\,
    
is really handy for doing up module instantiations
*/ 

`ifdef ICARUS_VERILOG
`include "dbg_guv.v"
`endif

`include "macros.vh"

module dbg_guv_tb # (
    parameter DATA_WIDTH = 64,
    parameter DEST_WIDTH = 16,
    parameter ID_WIDTH = 16,
    parameter CNT_SIZE = 16,
    parameter ADDR_WIDTH = 11, //This gives 2048 simultaneous debug cores
    parameter ADDR = 0, //Set this to be different for each 
    parameter RESET_TYPE = `NO_RESET,
    parameter DUT_RST_VAL = 0, //The value of DUT_rst that will reset the DUT
    parameter STICKY_MODE = 1, //If 1, latching registers does not reset them
    parameter PIPE_STAGE = 0, //This causes a delay on cmd_out in case fanout is
                              //an issue
    parameter SATCNT_WIDTH = 3 //Saturating ocunter for number of cycles slave
                               //has not been ready
);
	reg clk = 0;    
    reg rst = 0;
    
    //Input command stream
    //This may be a bad decision, but I decided the command width should match
    //the inject data width.
    //How does this work if you have a bunch of streams of different sizes that
    //you want to debug? Also, what about the rr_tree in that case?
    //Also, this core cannot assert backpressure
    reg [DATA_WIDTH -1:0] cmd_in_TDATA = 0;
    reg cmd_in_TVALID = 0;
    
    //All the controllers are daisy-chained. If in incoming command is not for
    //this controller, send it to the next one
    wire [DATA_WIDTH -1:0] cmd_out_TDATA;
    wire cmd_out_TVALID;
    
    //Also,since this module is intended to wrap around axis_governor, we need
    //to provide access to its ports through this one.
    
    //Input1 AXI Stream.
    reg [DATA_WIDTH-1:0] in1_TDATA = 0;
    reg in1_TVALID = 1;
    wire in1_TREADY;
    reg [DATA_WIDTH/8 -1:0] in1_TKEEP = 0;
    reg [DEST_WIDTH -1:0] in1_TDEST = 0;
    reg [ID_WIDTH -1:0] in1_TID = 0;
    reg in1_TLAST = 0;
    
    //Input2 AXI Stream.
    reg [DATA_WIDTH-1:0] in2_TDATA = 1;
    reg in2_TVALID = 1;
    wire in2_TREADY;
    reg [DATA_WIDTH/8 -1:0] in2_TKEEP = 1;
    reg [DEST_WIDTH -1:0] in2_TDEST = 1;
    reg [ID_WIDTH -1:0] in2_TID = 1;
    reg in2_TLAST = 0;
    
    //Output1 AXI Stream.
    wire [DATA_WIDTH-1:0] out1_TDATA;
    wire out1_TVALID;
    reg out1_TREADY = 1;
    wire [DATA_WIDTH/8 -1:0] out1_TKEEP;
    wire [DEST_WIDTH -1:0] out1_TDEST;
    wire [ID_WIDTH -1:0] out1_TID;
    wire out1_TLAST;
    
    //Output2 AXI Stream.
    wire [DATA_WIDTH-1:0] out2_TDATA;
    wire out2_TVALID;
    reg out2_TREADY = 1;
    wire [DATA_WIDTH/8 -1:0] out2_TKEEP;
    wire [DEST_WIDTH -1:0] out2_TDEST;
    wire [ID_WIDTH -1:0] out2_TID;
    wire out2_TLAST;
    
    //Log1 AXI Stream. 
    //This core takes care of concatting the sidechannels into the data part
    //of the flit
    `sim_out_axis_l(log_catted1, DATA_WIDTH + DATA_WIDTH/8);
    
    //Log2 AXI Stream. 
    //This core takes care of concatting the sidechannels into the data part
    //of the flit
    `sim_out_axis_l(log_catted2, DATA_WIDTH + DATA_WIDTH/8);
    
    integer fd, dummy;
    
    initial begin
        $dumpfile("dbg_guv.vcd");
        $dumpvars;
        $dumplimit(512000);
                
        fd = $fopen("dbg_guv_drivers.mem", "r");
        if (fd == 0) begin
            $display("Could not open file");
            $finish;
        end
        
        while ($fgetc(fd) != "\n") begin
            if ($feof(fd)) begin
                $display("Error: file is in incorrect format");
                $finish;
            end
        end
    end
    
    always #5 clk <= ~clk;
    
    always @(posedge clk) begin
        if ($feof(fd)) begin
            $display("Reached end of drivers file");
            #20
            $finish;
        end
        
        #0.01
        dummy = $fscanf(fd, "%x%b", cmd_in_TDATA, cmd_in_TVALID);
        //Skip comments at end of line
        while (!$feof(fd) && $fgetc(fd) != "\n") ;
    end
    
    reg [31:0] whatever;
    
    always @(posedge clk) begin
        if (`axis_flit(in1)) begin
            in1_TDATA <= in1_TDATA + 2;
            in1_TKEEP = ((1 << ($random & 32'b111)) -1);
            in1_TLAST = $random;
            in1_TDEST = $random;
            in1_TID = $random;
        end
        if (`axis_flit(in2)) begin
            in2_TDATA <= in2_TDATA + 2;
            in2_TKEEP = ((1 << ($random & 32'b111)) -1);
            in2_TLAST = $random;
            in2_TDEST = $random;
            in2_TID = $random;
        end
        
        whatever = $random;
        log_catted1_TREADY <= (| whatever[2:0]);
        //log_catted2_TREADY <= (| whatever[5:3]);
        out1_TREADY <= (| whatever[8:6]);
        out2_TREADY <= whatever[9];
    end
    
    //Wires from ctl1 to ctl2
    wire [DATA_WIDTH -1:0] cmd12_TDATA;
    wire cmd12_TVALID;
    
    dbg_guv # (
		.DATA_WIDTH(DATA_WIDTH),
		.DEST_WIDTH(DEST_WIDTH),
		.ID_WIDTH(ID_WIDTH),
		.CNT_SIZE(CNT_SIZE),
		.ADDR_WIDTH(ADDR_WIDTH), //This gives 1024 simultaneous debug cores
		.ADDR(0), //Set this to be different for each 
		.RESET_TYPE(RESET_TYPE),
		.STICKY_MODE(STICKY_MODE), //If 1, latching registers does not reset them
		.PIPE_STAGE(PIPE_STAGE) //This causes a delay on cmd_out in case fanout is
                                //an issue
    ) ctl1 (
		.clk(clk),
		.rst(rst),
        
		.cmd_in_TDATA(cmd_in_TDATA),
		.cmd_in_TVALID(cmd_in_TVALID),
        
		.cmd_out_TDATA(cmd12_TDATA),
		.cmd_out_TVALID(cmd12_TVALID),
        
        //Input AXI Stream.
		.din_TDATA(in1_TDATA),
		.din_TVALID(in1_TVALID),
		.din_TREADY(in1_TREADY),
		.din_TKEEP(in1_TKEEP),
		.din_TDEST(in1_TDEST),
		.din_TID(in1_TID),
		.din_TLAST(in1_TLAST),
        
        //Output AXI Stream.
		.dout_TDATA(out1_TDATA),
		.dout_TVALID(out1_TVALID),
		.dout_TREADY(out1_TREADY),
		.dout_TKEEP(out1_TKEEP),
		.dout_TDEST(out1_TDEST),
		.dout_TID(out1_TID),
		.dout_TLAST(out1_TLAST),
        
        //Log AXI Stream. 
        //This core takes care of concatting the sidechannels into the data part
        //of the flit
        `inst_axis_l(log_catted, log_catted1)
    );
    
    dbg_guv # (
		.DATA_WIDTH(DATA_WIDTH),
		.DEST_WIDTH(DEST_WIDTH),
		.ID_WIDTH(ID_WIDTH),
		.CNT_SIZE(CNT_SIZE),
		.ADDR_WIDTH(ADDR_WIDTH), //This gives 1024 simultaneous debug cores
		.ADDR(1), //Set this to be different for each 
		.RESET_TYPE(RESET_TYPE),
        .DUT_RST_VAL(DUT_RST_VAL),
		.STICKY_MODE(STICKY_MODE), //If 1, latching registers does not reset them
		.PIPE_STAGE(PIPE_STAGE), //This causes a delay on cmd_out in case fanout is
                                 //an issue
        .SATCNT_WIDTH(SATCNT_WIDTH)
    ) ctl2 (
		.clk(clk),
		.rst(rst),
        
		.cmd_in_TDATA(cmd12_TDATA),
		.cmd_in_TVALID(cmd12_TVALID),
        
		.cmd_out_TDATA(cmd_out_TDATA),
		.cmd_out_TVALID(cmd_out_TVALID),
        
        //Input AXI Stream.
		.din_TDATA(in2_TDATA),
		.din_TVALID(in2_TVALID),
		.din_TREADY(in2_TREADY),
		.din_TKEEP(in2_TKEEP),
		.din_TDEST(in2_TDEST),
		.din_TID(in2_TID),
		.din_TLAST(in2_TLAST),
        
        //Output AXI Stream.
		.dout_TDATA(out2_TDATA),
		.dout_TVALID(out2_TVALID),
		.dout_TREADY(out2_TREADY),
		.dout_TKEEP(out2_TKEEP),
		.dout_TDEST(out2_TDEST),
		.dout_TID(out2_TID),
		.dout_TLAST(out2_TLAST),
        
        //Log AXI Stream. 
        //This core takes care of concatting the sidechannels into the data part
        //of the flit
        `inst_axis_l(log_catted, log_catted2)
    );

endmodule
