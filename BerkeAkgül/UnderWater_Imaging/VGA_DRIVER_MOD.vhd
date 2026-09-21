library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity VGA_Driver_Mod is
    Port (
        clk_25mhz : in  std_logic;
        h_sync    : out std_logic;
        v_sync    : out std_logic;
        video_on  : out std_logic;
        pixel_x   : out integer;
        pixel_y   : out integer
    );
end VGA_Driver_Mod;

architecture Behavioral of VGA_Driver_Mod is

    -- 640x480 @ 60Hz Zamanlama Parametreleri (Yatay)
    constant H_DISPLAY       : integer := 640; -- Görünür alan
    constant H_FRONT_PORCH   : integer := 16;
    constant H_SYNC_PULSE    : integer := 96;
    constant H_BACK_PORCH    : integer := 48;
    constant H_TOTAL         : integer := 800; -- Toplam satır uzunluğu

    -- 640x480 @ 60Hz Zamanlama Parametreleri (Dikey)
    constant V_DISPLAY       : integer := 480; -- Görünür alan
    constant V_FRONT_PORCH   : integer := 10;
    constant V_SYNC_PULSE    : integer := 2;
    constant V_BACK_PORCH    : integer := 33;
    constant V_TOTAL         : integer := 525; -- Toplam kare yüksekliği

    -- Sayaçlar
    signal h_cnt_reg, h_cnt_next : integer range 0 to H_TOTAL - 1 := 0;
    signal v_cnt_reg, v_cnt_next : integer range 0 to V_TOTAL - 1 := 0;

begin

    -- Sayaç Güncelleme (Register)
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            h_cnt_reg <= h_cnt_next;
            v_cnt_reg <= v_cnt_next;
        end if;
    end process;

    -- Yatay ve Dikey Mantık
    process(h_cnt_reg, v_cnt_reg)
    begin
        -- Yatay sayaç mantığı
        if h_cnt_reg = H_TOTAL - 1 then
            h_cnt_next <= 0;
            -- Dikey sayaç mantığı (her satır bittiğinde bir artar)
            if v_cnt_reg = V_TOTAL - 1 then
                v_cnt_next <= 0;
            else
                v_cnt_next <= v_cnt_reg + 1;
            end if;
        else
            h_cnt_next <= h_cnt_reg + 1;
            v_cnt_next <= v_cnt_reg;
        end if;
    end process;

    -- Sync Sinyalleri (Genellikle Active Low - '0'da tetiklenir)
    h_sync <= '0' when (h_cnt_reg >= (H_DISPLAY + H_FRONT_PORCH) and 
                       h_cnt_reg < (H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE)) else '1';
                       
    v_sync <= '0' when (v_cnt_reg >= (V_DISPLAY + V_FRONT_PORCH) and 
                       v_cnt_reg < (V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE)) else '1';

    -- Video On Sinyali (Sadece görünür bölgedeyken '1' olur)
    video_on <= '1' when (h_cnt_reg < H_DISPLAY and v_cnt_reg < V_DISPLAY) else '0';

    -- Pixel Koordinatları
    pixel_x <= h_cnt_reg;
    pixel_y <= v_cnt_reg;

end Behavioral;