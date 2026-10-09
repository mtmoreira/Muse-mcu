# spiflash.v qualification checklist

Source: `spiflash.v`, YosysHQ/picorv32 `picosoc/spiflash.v`,
upstream HEAD `ef203c2b0a3fb793280f5114941416c425c5b461`, vendored
byte-identical (no modifications). ISC license (see header comment in the file).

All answers below are quoted from the model source.

## 1. Does it support the 0x03 READ command? YES

Header comment:

```
    // Supported commands:
    //    AB, B9, FF, 03, BB, EB, ED
```

Command decode in `spi_action`:

```
    if (powered_up && spi_cmd == 'h 03) begin
        if (bytecount == 2)
            spi_addr[23:16] = buffer;

        if (bytecount == 3)
            spi_addr[15:8] = buffer;

        if (bytecount == 4)
            spi_addr[7:0] = buffer;

        if (bytecount >= 4) begin
            buffer = memory[spi_addr];
            spi_addr = spi_addr + 1;
        end
    end
```

Protocol: 1 command byte (0x03) + 3 address bytes (24-bit, MSB-first),
then the memory contents stream out auto-incrementing. Data is shifted
out MSB-first: `io1_dout = buffer[7];` (MISO = io1), sampled in MSB-first:
`buffer = {buffer, io0};` (MOSI = io0).

## 2. SPI mode 0 (CPOL=0, CPHA=0)? YES

Inputs are sampled on the rising clock edge:

```
    always @(posedge clk) begin
        if (!csb) begin
            ...
            case (mode)
                mode_spi: begin
                    buffer = {buffer, io0};
```

Outputs are driven while the clock is LOW (i.e. change on the falling
edge, sampled by the master on the rising edge = CPHA=0):

```
    always @(csb, clk) begin
        spi_io_vld = 0;
        if (!csb && !clk) begin
            ...
            case (mode)
                mode_spi: begin
                    io0_oe = 0;
                    io1_oe = 1;
                    io2_oe = 0;
                    io3_oe = 0;
                    io1_dout = buffer[7];
                end
```

Mode-0 sampling (MOSI sampled rising, MISO changed falling) confirmed.
The model also uses 1 ns delays: inputs sampled 1 ns before the edge,
outputs updated 1 ns after, per the header comment.

## 3. CS behavior: active-low, deselect between commands? YES

Port is named `csb` (chip-select-bar). All transfer logic is gated on
`!csb`:

```
    always @(posedge clk) begin
        if (!csb) begin
```

Deselecting (CS high) aborts/resets the transaction state:

```
    always @(csb) begin
        if (csb) begin
            ...
            buffer = 0;
            bitcount = 0;
            bytecount = 0;
            mode = mode_spi;
            io0_oe = 0;
            io1_oe = 0;
            io2_oe = 0;
            io3_oe = 0;
```

Each CS assertion starts a fresh command; CS must go high between
commands. `mode` returns to `mode_spi` on deselect. (XIP mode via
`xip_cmd` is the only exception: it replays the last command on the
next CS assertion until 0xFF clears it; not used by our firmware.)

## 4. Power-on/reset state: NOT ready. 0xAB wake-up required.

```
    reg powered_up = 0;
```

The model powers up in the power-down state. The 0x03 read path (and
all other data commands) are gated on `powered_up`:

```
    if (powered_up && spi_cmd == 'h 03) begin
```

Wake-up is the 0xAB command, which is not itself gated:

```
    if (bytecount == 1) begin
        spi_cmd = buffer;

        if (spi_cmd == 8'h ab)
            powered_up = 1;

        if (spi_cmd == 8'h b9)
            powered_up = 0;
```

**Consequence for A8/D1:** the firmware SPI driver must issue a single
0xAB byte (CS assert, 8 clocks, CS deassert) before any 0x03 read.
The acceptance manifest's "power-on ready" assumption is incorrect for
this model and must be updated.

## 5. Other properties relevant to the testbench

- Memory: 16 MB array `reg [7:0] memory [0:16*1024*1024-1];`,
  preloaded at time 0 via `$readmemh` from the `+firmware=<file>` plusarg
  (default `firmware.hex`):

```
    reg [1023:0] firmware_file;
    initial begin
        if (!$value$plusargs("firmware=%s", firmware_file))
            firmware_file = "firmware.hex";
        $readmemh(firmware_file, memory);
    end
```

- No busy/program/erase behavior is modeled; reads are immediate.
- `localparam verbose = 0;` silences the debug `$write` tracing.
