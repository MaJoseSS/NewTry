/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`//default_nettype none

module tt_um_uart (
    input clk,
    input rst_n,
    input ena,
    input [7:0] ui_in,
    output [7:0] uo_out,
    input [7:0] uio_in,
    output [7:0] uio_out,
    output [7:0] uio_oe
);

    wire rst        = ~rst_n;
    wire [4:0] ctrl_word = ui_in[4:0];
    wire tx_start  = ui_in[5];
    wire baud16_en = ui_in[6];
    wire rx_in     = ui_in[7];

    wire [7:0] tx_data = uio_in;
    wire [7:0] rx_data;
    wire rx_ready;
    wire rx_error;
    wire tx_busy;
    wire tx_out;

    uart uart_inst (
        .clk(clk),
        .rst(rst),
        .ctrl_word(ctrl_word),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy),
        .tx_out(tx_out),
        .rx_in(rx_in),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .rx_error(rx_error),
        .baud16_en(baud16_en)
    );

    assign uo_out[0] = tx_out;
    assign uo_out[1] = tx_busy;
    assign uo_out[2] = rx_ready;
    assign uo_out[3] = rx_error;
    assign uo_out[7:4] = 4'b0;

    assign uio_out = rx_data;
    assign uio_oe  = 8'hFF;

endmodule

// ====================== Módulo UART ============================
module uart (
    input clk,
    input rst,
    input [4:0] ctrl_word, 
    input [7:0] tx_data,
    input tx_start,
    output tx_busy,
    output tx_out,
    input rx_in,
    output [7:0] rx_data,
    output rx_ready,
    output rx_error,
    input baud16_en
);

    localparam TX_IDLE  = 0;
    localparam TX_START = 1;
    localparam TX_DATA  = 2;
    localparam TX_PARITY = 3;
    localparam TX_STOP  = 4;

    localparam RX_IDLE  = 0;
    localparam START_CHECK = 1;
    localparam RX_DATA  = 2;
    localparam RX_PARITY = 3;
    localparam RX_STOP  = 4;

    reg [2:0] tx_state;
    reg [4:0] tx_cycle_count;
    reg [2:0] tx_bit_count;
    reg [7:0] tx_shift_reg;
    reg tx_parity_bit;
    reg [4:0] tx_stop_duration;
    reg tx_out_reg;

    reg [2:0] rx_state;
    reg [4:0] rx_cycle_count;
    reg [2:0] rx_bit_count;
    reg [7:0] rx_shift_reg;
    reg rx_in_prev;
    reg frame_error;
    reg parity_error;
    reg [7:0] rx_data_reg;
    reg rx_ready_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_out_reg <= 1'b1;
            tx_cycle_count <= 0;
            tx_bit_count <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_out_reg <= 1'b1;
                    if (tx_start) begin
                        tx_stop_duration <= (ctrl_word[4]) ? 
                            ((ctrl_word[1:0] == 2'b11) ? 24 : 32) : 16;
                        if (~ctrl_word[3]) begin
                            if (ctrl_word[2])
                                tx_parity_bit <= ^tx_data;
                            else
                                tx_parity_bit <= ~^tx_data;
                        end
                        tx_shift_reg <= tx_data;
                        tx_state <= TX_START;
                        tx_cycle_count <= 0;
                    end
                end
                TX_START: begin
                    tx_out_reg <= 1'b0;
                    if (baud16_en) begin
                        if (tx_cycle_count < 15)
                            tx_cycle_count <= tx_cycle_count + 1;
                        else begin
                            tx_cycle_count <= 0;
                            tx_state <= TX_DATA;
                            tx_bit_count <= 0;
                        end
                    end
                end
                TX_DATA: begin
                    tx_out_reg <= tx_shift_reg[0];
                    if (baud16_en) begin
                        if (tx_cycle_count < 15) begin
                            tx_cycle_count <= tx_cycle_count + 1;
                        end else begin
                            tx_cycle_count <= 0;
                            tx_shift_reg <= tx_shift_reg >> 1;
                            tx_bit_count <= tx_bit_count + 1;
                            if (tx_bit_count == (ctrl_word[1:0] + 4)) begin
                                if (~ctrl_word[3])
                                    tx_state <= TX_PARITY;
                                else
                                    tx_state <= TX_STOP;
                            end
                        end
                    end
                end
                TX_PARITY: begin
                    tx_out_reg <= tx_parity_bit;
                    if (baud16_en) begin
                        if (tx_cycle_count < 15)
                            tx_cycle_count <= tx_cycle_count + 1;
                        else begin
                            tx_cycle_count <= 0;
                            tx_state <= TX_STOP;
                        end
                    end
                end
                TX_STOP: begin
                    tx_out_reg <= 1'b1;
                    if (baud16_en) begin
                        if (tx_cycle_count < tx_stop_duration - 1)
                            tx_cycle_count <= tx_cycle_count + 1;
                        else begin
                            tx_cycle_count <= 0;
                            tx_state <= TX_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    assign tx_busy = (tx_state != TX_IDLE);
    assign tx_out = tx_out_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_ready_reg <= 0;
            rx_cycle_count <= 0;
            rx_bit_count <= 0;
            rx_in_prev <= 1'b1;
            frame_error <= 0;
            parity_error <= 0;
        end else begin
            rx_ready_reg <= 0;
            rx_in_prev <= rx_in;
            case (rx_state)
                RX_IDLE: begin
                    if (rx_in_prev && !rx_in) begin
                        rx_state <= START_CHECK;
                        rx_cycle_count <= 7;
                    end
                end
                START_CHECK: begin
                    if (baud16_en) begin
                        if (rx_cycle_count > 0)
                            rx_cycle_count <= rx_cycle_count - 1;
                        else begin
                            if (!rx_in) begin
                                rx_state <= RX_DATA;
                                rx_cycle_count <= 0;
                                rx_bit_count <= 0;
                            end else
                                rx_state <= RX_IDLE;
                        end
                    end
                end
                RX_DATA: begin
                    if (baud16_en) begin
                        rx_cycle_count <= rx_cycle_count + 1;
                        if (rx_cycle_count == 8)
                            rx_shift_reg <= {rx_in, rx_shift_reg[7:1]};
                        if (rx_cycle_count == 15) begin
                            rx_cycle_count <= 0;
                            rx_bit_count <= rx_bit_count + 1;
                            if (rx_bit_count == (ctrl_word[1:0] + 4)) begin
                                if (~ctrl_word[3])
                                    rx_state <= RX_PARITY;
                                else
                                    rx_state <= RX_STOP;
                            end
                        end
                    end
                end
                RX_PARITY: begin
                    if (baud16_en) begin
                        rx_cycle_count <= rx_cycle_count + 1;
                        if (rx_cycle_count == 8) begin
                            if (ctrl_word[2]) begin
                                if (^rx_shift_reg != rx_in) 
                                    parity_error <= 1;
                            end else begin
                                if (~^rx_shift_reg != rx_in)
                                    parity_error <= 1;
                            end
                        end
                        if (rx_cycle_count == 15) begin
                            rx_cycle_count <= 0;
                            rx_state <= RX_STOP;
                        end
                    end
                end
                RX_STOP: begin
                    if (baud16_en) begin
                        rx_cycle_count <= rx_cycle_count + 1;
                        if (rx_cycle_count == 8)
                            if (!rx_in) frame_error <= 1;
                        if (rx_cycle_count == 15) begin
                            rx_data_reg <= rx_shift_reg;
                            rx_ready_reg <= 1'b1;
                            rx_state <= RX_IDLE;
                            frame_error <= 0;
                            parity_error <= 0;
                        end
                    end
                end
            endcase
        end
    end

    assign rx_data = rx_data_reg;
    assign rx_ready = rx_ready_reg;
    assign rx_error = frame_error | parity_error;

endmodule

