library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================
--  OV7670 -> RAM Writer  (RGB444 in -> RGB332 out)
--
--  Datasheet Figure 13'e göre RGB444 byte yapısı:
--
--  First Byte (hi):
--    D[7:4] = 0000  (kullanılmıyor, x)
--    D[3]   = R3
--    D[2]   = R2
--    D[1]   = R1
--    D[0]   = R0
--
--  Second Byte (lo):
--    D[7]   = G3
--    D[6]   = G2
--    D[5]   = G1
--    D[4]   = G0
--    D[3]   = B3
--    D[2]   = B2
--    D[1]   = B1
--    D[0]   = B0
--
--  RGB444 -> RGB332 dönüşümü (en anlamlı bitler alınır):
--    R[2:0] = hi[3:1]   (R3,R2,R1 -> 4-bit R'nin üst 3 biti)
--    G[2:0] = lo[7:5]   (G3,G2,G1 -> 4-bit G'nin üst 3 biti)
--    B[1:0] = lo[3:2]   (B3,B2    -> 4-bit B'nin üst 2 biti)
--
--  Çıkış byte: [7:5]=R  [4:2]=G  [1:0]=B
--
--  NOT: RGB444 register ayarı için:
--    RGB444 (0x8C) = 0x02  : RGB444 enable, xRGB formatı
--    COM15  (0x40) = 0xC0  : full range, RGB565/555 kapalı
-- =============================================================

entity ov7670_to_ram_writer is
  port(
    cam_pclk  : in  std_logic;
    cam_vsync : in  std_logic;
    cam_href  : in  std_logic;
    cam_d     : in  std_logic_vector(7 downto 0);
    reset_n   : in  std_logic := '1';

    select_rgb : in std_logic; -- '0' = RGB444, '1' = YUV422 (şimdilik kullanılmıyor)


    -- RAM çıkışları (RGB332, 8-bit)
    -- [7:5]=R(2:0)  [4:2]=G(2:0)  [1:0]=B(1:0)
    o_wr_en   : out std_logic;
    o_wr_x    : out unsigned(9 downto 0);
    o_wr_y    : out unsigned(8 downto 0);
    o_wr_data : out std_logic_vector(11 downto 0)
  );
end entity;

architecture rtl of ov7670_to_ram_writer is

  signal x_cnt     : integer range 0 to 1023 := 0;
  signal y_cnt     : integer range 0 to 511  := 0;
  signal p_cnt     : integer range 0 to 1    := 0; -- piksel baytı sayacı (0 veya 1)

  signal cam_d_prev : std_logic_vector(7 downto 0) := (others => '0');
  signal href_prev : std_logic := '0';

  function clamp8(x : signed(8 downto 0)) return unsigned is
  begin
    if x < 32      then return to_unsigned(32,   8);
    elsif x > 240 then return to_unsigned(240, 8);
    else          return unsigned(x(7 downto 0));
    end if;
  end function;

begin

  p_writer : process(cam_pclk, reset_n)
  begin
    if reset_n = '0' then
      x_cnt     <= 0;
      y_cnt     <= 0;
      href_prev <= '0';
      o_wr_en   <= '0';
      o_wr_x    <= (others => '0');
      o_wr_y    <= (others => '0');
      o_wr_data <= (others => '0');

    elsif rising_edge(cam_pclk) then
      o_wr_en   <= '0';
      href_prev <= cam_href;
      cam_d_prev <= cam_d;

      -- VSYNC: yeni frame başlıyor
      if cam_vsync = '1' then
        x_cnt   <= 0;
        y_cnt   <= 0;
        p_cnt   <= 0;

      -- HREF aktif: piksel baytları geliyor
      elsif cam_href = '1' then
        
        if p_cnt = 0 then
          p_cnt <= 1; -- ilk bayt alındı, ikinci bayta geç
        else
          p_cnt <= 0; -- ikinci bayt alındı, sıradaki piksele geç

          if (x_cnt < 640) and (y_cnt < 480) then
            o_wr_en   <= '1';
            o_wr_data(11 downto 6) <= cam_d(7 downto 2); -- Y1Y2
            o_wr_data(5 downto 0) <= cam_d_prev(7 downto 2); -- UV
            o_wr_x    <= to_unsigned(x_cnt, 10);
            o_wr_y    <= to_unsigned(y_cnt,  9);
          end if;

          if x_cnt < 1023 then
            x_cnt <= x_cnt + 1;
          end if;
        end if;

        


      -- HREF düşen kenar: satır sonu
      elsif href_prev = '1' then
        x_cnt   <= 0;

        if y_cnt < 511 then
          y_cnt <= y_cnt + 1;
        end if;

      end if;
    end if;
  end process p_writer;

end architecture;