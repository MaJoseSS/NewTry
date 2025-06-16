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

    // =========================================================================
    // Interfaz de usuario mapeada a señales UART internas
    // =========================================================================
    wire rst        = ~rst_n;
    wire [4:0] ctrl_word = ui_in[4:0];
    wire tx_start  = ui_in[5];
    wire baud16_en = ui_in[6];
    wire rx_in     = ui_in[7];

    wire [7:0] tx_data = uio_in; // 8 bits de datos para transmitir
    wire [7:0] rx_data;
    wire rx_ready;
    wire rx_error;
    wire tx_busy;
    wire tx_out;

    // =========================================================================
    // UART original instanciado aquí
    // =========================================================================
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

    // =========================================================================
    // Asignación de salida
    // =========================================================================
    assign uo_out[0] = tx_out;
    assign uo_out[1] = tx_busy;
    assign uo_out[2] = rx_ready;
    assign uo_out[3] = rx_error;
    assign uo_out[7:4] = 4'b0;

    assign uio_out = rx_data;
    assign uio_oe  = 8'hFF; // rx_data siempre disponible en uio_out

endmodule

endmodule
