library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================
--  OV7670 Init Controller - Üst Modül
--
--  ov7670_registers  : Register ROM (hangi reg, hangi değer)
--  i2c_sender        : I2C/SCCB bit gönderici
--
--  Akış:
--    1. start='1' gelince güç açılış bekleme
--    2. ROM'dan sırayla {reg, data} al
--    3. i2c_sender'a gönder (taken='1' bekle)
--    4. Gönderim bitince (busy_sr=0) advance='1' ver -> sonraki reg
--    5. fin='1' olunca init_done='1'
-- =============================================================
entity ov7670_init_top is
  generic(
    G_CLK_HZ  : integer                      := 100_000_000;
    G_PUP_MS  : integer                      := 20;
    G_DEV7    : std_logic_vector(6 downto 0) := "0100001"  -- OV7670 = 0x21
  );
  port(
    clk       : in    std_logic;
    rst_n     : in    std_logic;
    start     : in    std_logic;
    busy      : out   std_logic;
    init_done : out   std_logic;
    scl       : out   std_logic;
    sda       : inout std_logic
  );
end entity;

architecture rtl of ov7670_init_top is

  -- -----------------------------------------------------------
  -- Bileşen bildirimleri
  -- -----------------------------------------------------------
  component ov7670_registers is
    port(
      clk     : in  std_logic;
      resend  : in  std_logic;
      advance : in  std_logic;
      reg_out : out std_logic_vector(15 downto 0);
      fin     : out std_logic
    );
  end component;

  component i2c_sender is
    port(
      clk      : in    std_logic;
      siod     : inout std_logic;
      sioc     : out   std_logic;
      taken    : out   std_logic;
      send     : in    std_logic;
      dev_id   : in    std_logic_vector(7 downto 0);
      reg_addr : in    std_logic_vector(7 downto 0);
      value    : in    std_logic_vector(7 downto 0)
    );
  end component;

  -- -----------------------------------------------------------
  -- İç sinyaller
  -- -----------------------------------------------------------
  -- ROM arayüzü
  signal rom_resend  : std_logic := '0';
  signal rom_advance : std_logic := '0';
  signal rom_out     : std_logic_vector(15 downto 0);
  signal rom_fin     : std_logic;

  -- I2C sender arayüzü
  signal i2c_send    : std_logic := '0';
  signal i2c_taken   : std_logic;

  -- ms tick
  constant C_MS_DIV : integer := G_CLK_HZ / 1000;
  signal ms_cnt      : integer range 0 to C_MS_DIV - 1 := 0;
  signal ms_tick     : std_logic := '0';

  -- i2c_sender'ın meşgul olup olmadığını izlemek için
  -- taken='1' gelince meşgul, bir sonraki taken='1' veya
  -- belirli süre sonra serbest. Orijinal tasarımda divider=0
  -- koşulu ile bir sonraki send kabul ediliyor.
  -- Biz taken='1' ile senkronize ederiz.
  signal send_pend   : std_logic := '0';   -- gönderim bekleniyor

  -- Top FSM
  type t_top is (
    TOP_IDLE,
    TOP_PUP,        -- güç açılış bekleme
    TOP_RESEND,     -- ROM'u sıfırla
    TOP_LOAD,       -- ROM çıkışını bekle (1 clk gecikme)
    TOP_SEND,       -- i2c_sender'a gönder
    TOP_WAIT_TAKEN, -- taken='1' bekle
    TOP_WAIT_NEXT,  -- bir sonraki kayda geçmeden önce bekle
    TOP_ADVANCE,    -- ROM'u ilerlet
    TOP_OK          -- tamamlandı
  );
  signal top_st  : t_top := TOP_IDLE;
  signal ms_wait : integer range 0 to 1023 := 0;

begin

  -- -----------------------------------------------------------
  -- Bileşen bağlantıları
  -- -----------------------------------------------------------
  u_regs : ov7670_registers
    port map(
      clk     => clk,
      resend  => rom_resend,
      advance => rom_advance,
      reg_out => rom_out,
      fin     => rom_fin
    );

  u_i2c : i2c_sender
    port map(
      clk      => clk,
      siod     => sda,
      sioc     => scl,
      taken    => i2c_taken,
      send     => i2c_send,
      dev_id   => G_DEV7 & '0',
      reg_addr => rom_out(15 downto 8),  -- üst byte = register adresi
      value    => rom_out(7  downto 0)   -- alt byte  = data
    );

  -- -----------------------------------------------------------
  -- Çıkışlar
  -- -----------------------------------------------------------
  busy      <= '0' when (top_st = TOP_IDLE or top_st = TOP_OK) else '1';
  init_done <= '1' when top_st = TOP_OK else '0';

  -- -----------------------------------------------------------
  -- ms tick
  -- -----------------------------------------------------------
  p_ms : process(clk, rst_n)
  begin
    if rst_n = '0' then
      ms_cnt  <= 0;
      ms_tick <= '0';
    elsif rising_edge(clk) then
      ms_tick <= '0';
      if ms_cnt = C_MS_DIV - 1 then
        ms_cnt  <= 0;
        ms_tick <= '1';
      else
        ms_cnt <= ms_cnt + 1;
      end if;
    end if;
  end process p_ms;

  -- -----------------------------------------------------------
  -- Top Sequencer
  -- -----------------------------------------------------------
  p_top : process(clk, rst_n)
  begin
    if rst_n = '0' then
      top_st     <= TOP_IDLE;
      ms_wait    <= 0;
      rom_resend  <= '0';
      rom_advance <= '0';
      i2c_send    <= '0';

    elsif rising_edge(clk) then
      -- Varsayılan: pulse sinyaller
      rom_resend  <= '0';
      rom_advance <= '0';
      i2c_send    <= '0';

      case top_st is

        -- -------------------------------------------------
        when TOP_IDLE =>
          if start = '1' then
            ms_wait <= G_PUP_MS;
            top_st  <= TOP_PUP;
          end if;

        -- -------------------------------------------------
        -- Güç açılış bekleme
        when TOP_PUP =>
          if ms_tick = '1' then
            if ms_wait > 0 then
              ms_wait <= ms_wait - 1;
            else
              top_st <= TOP_RESEND;
            end if;
          end if;

        -- -------------------------------------------------
        -- ROM'u başa al (resend=1 -> addr=0)
        when TOP_RESEND =>
          rom_resend <= '1';
          top_st     <= TOP_LOAD;

        -- -------------------------------------------------
        -- ROM çıkışının güncellenmesi için 1 clk bekle
        when TOP_LOAD =>
          top_st <= TOP_SEND;

        -- -------------------------------------------------
        -- Sentinel kontrolü + gönderim başlat
        when TOP_SEND =>
          if rom_fin = '1' then
            -- 0xFFFF -> tamamlandı
            top_st <= TOP_OK;
          else
            i2c_send <= '1';
            top_st   <= TOP_WAIT_TAKEN;
          end if;

        -- -------------------------------------------------
        -- i2c_sender tampona alana kadar bekle
        when TOP_WAIT_TAKEN =>
          i2c_send <= '1';   -- taken gelene kadar send'i yüksek tut
          if i2c_taken = '1' then
            i2c_send <= '0';
            top_st   <= TOP_WAIT_NEXT;
            -- İki tam divider çevrimi beklemek yeterli.
            -- i2c_sender 256 clk'ta bir bit geçiyor,
            -- 32 bit * 256 = 8192 clk beklemek gerekiyor.
            -- ms_wait ile bekleyeceğiz: 100MHz'de 1ms=100k clk > 8192
            ms_wait  <= 1;   -- 1ms bekle (fazlasıyla yeterli)
          end if;

        -- -------------------------------------------------
        -- Gönderim bitmesini bekle (1ms)
        when TOP_WAIT_NEXT =>
          if ms_tick = '1' then
            if ms_wait > 0 then
              ms_wait <= ms_wait - 1;
            else
              top_st <= TOP_ADVANCE;
            end if;
          end if;

        -- -------------------------------------------------
        -- ROM'u bir ilerlet
        when TOP_ADVANCE =>
          rom_advance <= '1';
          top_st      <= TOP_LOAD;

        -- -------------------------------------------------
        when TOP_OK =>
          -- Yeniden başlatma desteği
          --if start = '1' then
          --  ms_wait <= G_PUP_MS;
          --  top_st  <= TOP_PUP;
          --end if;

      end case;
    end if;
  end process p_top;

end architecture;
