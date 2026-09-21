-- ov7670_model.vhd
-- VHDL-2008 testbench modeli (SCCB fiziksel yok, ama register write portu var)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ov7670_model is
  generic (
    -- Byte clock (PCLK) period
    G_PCLK_PERIOD : time := 40 ns; -- 25 MHz byte clock

    -- Datasheet VGA timing (Figure 6)
    G_H_PIXELS    : natural := 640; -- active pixels
    G_H_TOTAL     : natural := 784; -- total "pixel times" per line (tLINE = 784*tP)
    G_V_ACTIVE    : natural := 480; -- active lines
    G_V_TOTAL     : natural := 510; -- total lines per frame

    -- tP = 2*tPCLK for YUV/RGB in datasheet -> we output 2 bytes/pixel
    -- So per line total PCLK cycles = G_H_TOTAL*2, active = G_H_PIXELS*2.

    -- Simple pattern
    G_TESTPATTERN : boolean := true
  );
  port (
    -- Clocks/Control
    reset_n : in  std_logic := '1';
    enable  : in  std_logic := '1';

    -- OV7670-like outputs
    pclk    : out std_logic;
    vsync   : out std_logic;
    href    : out std_logic;
    d       : out std_logic_vector(7 downto 0);

    -- "Pseudo-SCCB" register write (TB drives these)
    reg_wr_en   : in  std_logic := '0';
    reg_addr    : in  std_logic_vector(7 downto 0) := (others => '0');
    reg_wdata   : in  std_logic_vector(7 downto 0) := (others => '0')
  );
end entity;

architecture tb of ov7670_model is
  -- -------------------------
  -- Register file (subset)
  -- -------------------------
  signal r_COM7  : std_logic_vector(7 downto 0) := x"00"; -- 0x12 default 0x00
  signal r_COM10 : std_logic_vector(7 downto 0) := x"00"; -- 0x15 default 0x00
  signal r_COM13 : std_logic_vector(7 downto 0) := x"88"; -- 0x3D default 0x88
  signal r_COM15 : std_logic_vector(7 downto 0) := x"C0"; -- 0x40 default 0xC0
  signal r_TSLB  : std_logic_vector(7 downto 0) := x"0D"; -- 0x3A default 0x0D
  signal r_RGB444: std_logic_vector(7 downto 0) := x"00"; -- 0x8C default 0x00

  -- -------------------------
  -- Timing counters
  -- -------------------------
  constant C_LINE_PCLK_TOTAL  : natural := G_H_TOTAL  * 2;
  constant C_LINE_PCLK_ACTIVE : natural := G_H_PIXELS * 2;

  signal pclk_i  : std_logic := '0';
  signal vsync_i : std_logic := '0';
  signal href_i  : std_logic := '0';
  signal d_i     : std_logic_vector(7 downto 0) := (others => '0');

  signal line_cnt   : natural range 0 to G_V_TOTAL-1 := 0; -- 0..509
  signal pclk_cnt   : natural range 0 to C_LINE_PCLK_TOTAL-1 := 0; -- 0..(784*2-1)
  signal pix_cnt    : natural range 0 to G_H_PIXELS-1 := 0; -- active pixel index
  signal byte_phase : natural range 0 to 3 := 0; -- for YUV422 (4 bytes per 2 pixels)

  -- -------------------------
  -- Helpers
  -- -------------------------
  function clamp_u8(v : integer) return std_logic_vector is
    variable t : integer := v;
  begin
    if t < 0 then t := 0; end if;
    if t > 255 then t := 255; end if;
    return std_logic_vector(to_unsigned(t, 8));
  end function;

  function imax(a : integer; b : integer) return integer is
begin
  if a > b then return a; else return b; end if;
end function;


procedure gen_rgb(
  constant x : in natural;
  constant y : in natural;
  variable r : out integer;
  variable g : out integer;
  variable b : out integer
) is
  variable r0, g0, b0 : integer;
  variable denom      : integer;
begin
  if G_TESTPATTERN then
    -- 3-color bars
    if x < G_H_PIXELS/3 then
      r0 := 255; g0 := 0;   b0 := 0;
    elsif x < 2*G_H_PIXELS/3 then
      r0 := 0;   g0 := 255; b0 := 0;
    else
      r0 := 0;   g0 := 0;   b0 := 255;
    end if;

    -- vertical gradient on GREEN (out paramı okumadan!)
    denom := imax(1, integer(G_V_ACTIVE) - 1);
    g0 := (g0 * integer(y)) / denom;

    r := r0; g := g0; b := b0;
  else
    r := 64; g := 64; b := 64;
  end if;
end procedure;

  procedure rgb_to_yuv601(
    constant r  : in integer;
    constant g  : in integer;
    constant b  : in integer;
    variable y  : out integer;
    variable u  : out integer;
    variable v  : out integer
  ) is
  begin
    -- integer approx BT.601
    y := (  77*r + 150*g +  29*b) / 256;
    u := ((-43*r -  85*g + 128*b) / 256) + 128;
    v := ((128*r - 107*g -  21*b) / 256) + 128;
  end procedure;

  function is_rgb_mode(com7 : std_logic_vector(7 downto 0)) return boolean is
  begin
    -- COM7[2]=RGB select, COM7[0]=RAW select. RGB mode is (2=1,0=0)
    return (com7(2) = '1' and com7(0) = '0');
  end function;

  function yuv_order(tslb : std_logic_vector(7 downto 0);
                     com13: std_logic_vector(7 downto 0)) return natural is
    -- Map datasheet:
    -- TSLB[3], COM13[0]:
    -- 00: Y U Y V  (YUYV)
    -- 01: Y V Y U  (YVYU)
    -- 10: U Y V Y  (UYVY)
    -- 11: V Y U Y  (VYUY)
    variable key : std_logic_vector(1 downto 0);
  begin
    key := tslb(3) & com13(0);
    case key is
      when "00" => return 0; -- YUYV
      when "01" => return 1; -- YVYU
      when "10" => return 2; -- UYVY
      when others => return 3; -- VYUY
    end case;
  end function;

begin
  pclk  <= pclk_i;
  vsync <= vsync_i;
  href  <= href_i;
  d     <= d_i;

  -- -------------------------
  -- Register writes (TB-driven)
  -- -------------------------
  regfile : process
  begin
    wait until rising_edge(pclk_i);
    if reset_n = '0' then
      r_COM7   <= x"00";
      r_COM10  <= x"00";
      r_COM13  <= x"88";
      r_COM15  <= x"C0";
      r_TSLB   <= x"0D";
      r_RGB444 <= x"00";
    else
      if reg_wr_en = '1' then
        case reg_addr is
          when x"12" => r_COM7   <= reg_wdata;
          when x"15" => r_COM10  <= reg_wdata;
          when x"3D" => r_COM13  <= reg_wdata;
          when x"40" => r_COM15  <= reg_wdata;
          when x"3A" => r_TSLB   <= reg_wdata;
          when x"8C" => r_RGB444 <= reg_wdata;
          when others => null;
        end case;
      end if;
    end if;
  end process;

  -- -------------------------
  -- PCLK generator (byte clock)
  -- -------------------------
  pclk_gen : process
  begin
    wait for G_PCLK_PERIOD/2;
    if enable='1' and reset_n='1' then
      pclk_i <= not pclk_i;
    else
      pclk_i <= '0';
    end if;
  end process;

  -- -------------------------
  -- Video timing + data
  -- - Data prepared just before rising edge is sampled in TB/capture
  -- -------------------------
  video : process
    variable r0,g0,b0 : integer;
    variable r1,g1,b1 : integer;
    variable y0,u0,v0 : integer;
    variable y1,u1,v1 : integer;
    variable u_sh, v_sh : integer;
    variable ord : natural;

    variable hi_byte, lo_byte : std_logic_vector(7 downto 0);
    variable rr,gg,bb : integer;
  begin
    -- init
    vsync_i <= '0';
    href_i  <= '0';
    d_i     <= (others => '0');

    line_cnt   <= 0;
    pclk_cnt   <= 0;
    pix_cnt    <= 0;
    byte_phase <= 0;

    wait until reset_n='1';
    wait until rising_edge(pclk_i);

    while true loop
      wait until rising_edge(pclk_i);

      if enable='0' then
        vsync_i <= '0';
        href_i  <= '0';
        d_i     <= (others => '0');
        next;
      end if;

      -- VSYNC: pulse high for first 3 lines (datasheet shows 3*tLINE invalid/sync)
      if line_cnt < 3 then
        vsync_i <= '1';
      else
        vsync_i <= '0';
      end if;

      -- HREF: only during active video lines (after 3+17 blank lines)
      -- Active lines: lines [3+17 .. 3+17+479] = [20..499]
      if (line_cnt >= 20) and (line_cnt < 20 + G_V_ACTIVE) then
        -- inside an active line: HREF high for active byte window (640*2 PCLK)
        if pclk_cnt < C_LINE_PCLK_ACTIVE then
          href_i <= '1';
        else
          href_i <= '0';
        end if;
      else
        href_i <= '0';
      end if;

      -- Data generation when HREF high
      if href_i='1' then
        -- pixel index increments every 2 PCLK in RGB565,
        -- and every 4 PCLK for 2 pixels in YUV422 (but still 2 bytes/pixel avg).
        if is_rgb_mode(r_COM7) then
          -- RGB mode: implement RGB565 by COM15[5:4]=01 (typical)
          -- If not set, still output RGB565 for simplicity (most common).
          gen_rgb(pix_cnt, (line_cnt-20), rr, gg, bb);

          -- RGB565 pack:
          -- high = R[7:3] & G[7:5]
          -- low  = G[4:2] & B[7:3]
          hi_byte := std_logic_vector(to_unsigned(rr/8, 5) & to_unsigned(gg/32, 3));
          lo_byte := std_logic_vector(to_unsigned((gg/4) mod 8, 3) & to_unsigned(bb/8, 5));

          if (pclk_cnt mod 2) = 0 then
            d_i <= hi_byte;
          else
            d_i <= lo_byte;
            if pix_cnt = G_H_PIXELS-1 then
              pix_cnt <= 0;
            else
              pix_cnt <= pix_cnt + 1;
            end if;
          end if;

        else
          -- YUV422 mode (default)
          -- Produce two pixels per chroma pair, output order depends on TSLB[3] & COM13[0]
          ord := yuv_order(r_TSLB, r_COM13);

          gen_rgb(pix_cnt, (line_cnt-20), r0, g0, b0);
          if pix_cnt < G_H_PIXELS-1 then
            gen_rgb(pix_cnt+1, (line_cnt-20), r1, g1, b1);
          else
            r1 := r0; g1 := g0; b1 := b0;
          end if;

          rgb_to_yuv601(r0,g0,b0, y0,u0,v0);
          rgb_to_yuv601(r1,g1,b1, y1,u1,v1);

          u_sh := (u0 + u1) / 2;
          v_sh := (v0 + v1) / 2;

          -- byte_phase cycles 0..3 for a 2-pixel group
          case ord is
            when 0 => -- Y U Y V (YUYV)
              case byte_phase is
                when 0 => d_i <= clamp_u8(y0); byte_phase <= 1;
                when 1 => d_i <= clamp_u8(u_sh); byte_phase <= 2;
                when 2 => d_i <= clamp_u8(y1); byte_phase <= 3;
                when others =>
                  d_i <= clamp_u8(v_sh); byte_phase <= 0;
                  if pix_cnt >= G_H_PIXELS-2 then
                    pix_cnt <= 0;
                  else
                    pix_cnt <= pix_cnt + 2;
                  end if;
              end case;

            when 1 => -- Y V Y U (YVYU)
              case byte_phase is
                when 0 => d_i <= clamp_u8(y0); byte_phase <= 1;
                when 1 => d_i <= clamp_u8(v_sh); byte_phase <= 2;
                when 2 => d_i <= clamp_u8(y1); byte_phase <= 3;
                when others =>
                  d_i <= clamp_u8(u_sh); byte_phase <= 0;
                  if pix_cnt >= G_H_PIXELS-2 then
                    pix_cnt <= 0;
                  else
                    pix_cnt <= pix_cnt + 2;
                  end if;
              end case;

            when 2 => -- U Y V Y (UYVY)
              case byte_phase is
                when 0 => d_i <= clamp_u8(u_sh); byte_phase <= 1;
                when 1 => d_i <= clamp_u8(y0); byte_phase <= 2;
                when 2 => d_i <= clamp_u8(v_sh); byte_phase <= 3;
                when others =>
                  d_i <= clamp_u8(y1); byte_phase <= 0;
                  if pix_cnt >= G_H_PIXELS-2 then
                    pix_cnt <= 0;
                  else
                    pix_cnt <= pix_cnt + 2;
                  end if;
              end case;

            when others => -- V Y U Y (VYUY)
              case byte_phase is
                when 0 => d_i <= clamp_u8(v_sh); byte_phase <= 1;
                when 1 => d_i <= clamp_u8(y0); byte_phase <= 2;
                when 2 => d_i <= clamp_u8(u_sh); byte_phase <= 3;
                when others =>
                  d_i <= clamp_u8(y1); byte_phase <= 0;
                  if pix_cnt >= G_H_PIXELS-2 then
                    pix_cnt <= 0;
                  else
                    pix_cnt <= pix_cnt + 2;
                  end if;
              end case;
          end case;
        end if;

      else
        -- during blanking
        d_i <= (others => '0');
        byte_phase <= 0;
        pix_cnt <= 0;
      end if;

      -- Advance horizontal counter
      if pclk_cnt = C_LINE_PCLK_TOTAL-1 then
        pclk_cnt <= 0;

        -- advance line
        if line_cnt = G_V_TOTAL-1 then
          line_cnt <= 0;
        else
          line_cnt <= line_cnt + 1;
        end if;
      else
        pclk_cnt <= pclk_cnt + 1;
      end if;

    end loop;
  end process;

end architecture;
