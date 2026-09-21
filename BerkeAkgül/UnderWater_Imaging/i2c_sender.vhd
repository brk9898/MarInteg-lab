library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================
--  I2C / SCCB Sender
--  Verilog i2c_sender.v dosyasından VHDL'e uyarlandı.
--
--  Orijinale sadık kalındı:
--    - 32-bit busy_sr (shift register) ile bit zamanlaması
--    - 32-bit data_sr ile gönderilecek veri
--    - 8-bit divider ile SCL faz kontrolü
--    - ACK pozisyonlarında SDA high-Z (SCCB don't-care)
--
--  Arayüz:
--    clk      : sistem clock (divider ile bölünür)
--    siod     : I2C SDA (inout, open-drain)
--    sioc     : I2C SCL (output)
--    taken    : '1' -> gönderme tampona alındı (1 clk pulse)
--    send     : '1' -> yeni veri gönder
--    dev_id   : cihaz adresi (7 bit + W=0 = 8 bit)
--    reg_addr : yazılacak register adresi
--    value    : yazılacak değer
-- =============================================================
entity i2c_sender is
  port(
    clk      : in    std_logic;
    siod     : inout std_logic;
    sioc     : out   std_logic;
    taken    : out   std_logic;
    send     : in    std_logic;
    dev_id   : in    std_logic_vector(7 downto 0);  -- {dev7, '0'}
    reg_addr : in    std_logic_vector(7 downto 0);
    value    : in    std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of i2c_sender is

  -- Orijinal Verilog'daki register isimleri korundu
  signal divider : unsigned(7 downto 0) := x"01";
  signal busy_sr : std_logic_vector(31 downto 0) := (others => '0');
  signal data_sr : std_logic_vector(31 downto 0) := (others => '1');

  -- SDA iç sürücü (inout için)
  signal siod_int : std_logic := '1';

begin

  -- -------------------------------------------------------
  -- SDA open-drain sürme:
  --   siod_int = 'Z' -> serbest bırak (pull-up high yapar)
  --   siod_int = '0' -> low çek
  --   siod_int = '1' -> Z gibi davranır (sürme yok)
  -- -------------------------------------------------------
  siod <= 'Z' when siod_int = '1' or siod_int = 'Z' else '0';

  -- -------------------------------------------------------
  -- SDA kombinasyonel mantığı (orijinal always @(busy_sr or data_sr[31]))
  -- ACK pencerelerinde SDA serbest bırakılır (slave sürüyor)
  -- Pozisyonlar: busy_sr[11:10]=10, [20:19]=10, [29:28]=10
  -- -------------------------------------------------------
  p_sda : process(busy_sr, data_sr)
  begin
    if (   (busy_sr(11 downto 10) = "10")
        or (busy_sr(20 downto 19) = "10")
        or (busy_sr(29 downto 28) = "10") ) then
      siod_int <= 'Z';   -- ACK penceresi: slave sürsün
    else
      siod_int <= data_sr(31);
    end if;
  end process p_sda;

  -- -------------------------------------------------------
  -- Ana clock process
  -- -------------------------------------------------------
  p_main : process(clk)
  begin
    if rising_edge(clk) then
      taken <= '0';   -- varsayılan: pulse değil

      if busy_sr(31) = '0' then
        -- ------------------------------------------------
        -- BUS BOŞ: SCL=1, send gelirse tampona al
        -- ------------------------------------------------
        sioc <= '1';

        if send = '1' then
          if divider = x"00" then
            -- Veriyi yükle:
            -- Format: [START=100] [id(7:0)] [0=W] [reg(7:0)] [0] [val(7:0)] [0] [STOP=01]
            -- Toplam: 3 + 8+1 + 8+1 + 8+1 + 2 = 32 bit
            data_sr <= "100"
                       & dev_id
                       & '0'
                       & reg_addr
                       & '0'
                       & value
                       & '0'
                       & "01";

            -- busy_sr: her bit için meşgul işareti
            -- 3 bit START + 9 bit*3 byte + 2 bit STOP = 32 bit
            busy_sr <= "111"
                       & "111111111"
                       & "111111111"
                       & "111111111"
                       & "11";

            taken <= '1';
          else
            divider <= divider + 1;
          end if;
        end if;

      else
        -- ------------------------------------------------
        -- TRANSFER DEVAM EDIYOR
        -- SCL fazı divider[7:6] ile belirlenir:
        --   00 -> LOW hazırlık
        --   01 -> HIGH (veri geçerli)
        --   10 -> HIGH (tutma)
        --   11 -> LOW  (hazırlık)
        --
        -- Özel durumlar busy_sr uç bitlerine göre seçilir
        -- ------------------------------------------------

        -- SCL mantığı (orijinal case yapısı)
        case busy_sr(31 downto 29) & busy_sr(2 downto 0) is

          -- START A: SCL=1
          when "111" & "111" =>
            sioc <= '1';

          -- START B: SCL=1
          when "111" & "110" =>
            sioc <= '1';

          -- START C: SCL=0 (SDA low yapılıyor)
          when "111" & "100" =>
            sioc <= '0';

          -- İlk bit başlangıcı
          when "110" & "000" =>
            case std_logic_vector(divider(7 downto 6)) is
              when "00"   => sioc <= '0';
              when others => sioc <= '1';
            end case;

          -- Son bit sonu
          when "100" & "000" =>
            sioc <= '1';

          -- STOP: SCL=1
          when "000" & "000" =>
            sioc <= '1';

          -- Normal bit: SCL low/high/low
          when others =>
            case std_logic_vector(divider(7 downto 6)) is
              when "00"   => sioc <= '0';
              when "01"   => sioc <= '1';
              when "10"   => sioc <= '1';
              when others => sioc <= '0';
            end case;

        end case;

        -- Shift registers: her divider overflow'unda bir bit kaydır
        if divider = x"FF" then
          busy_sr <= busy_sr(30 downto 0) & '0';
          data_sr <= data_sr(30 downto 0) & '1';
          divider <= x"00";
        else
          divider <= divider + 1;
        end if;

      end if;
    end if;
  end process p_main;

end architecture;
