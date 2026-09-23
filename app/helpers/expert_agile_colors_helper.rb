# The card colour screen.
module ExpertAgileColorsHelper
  # What the Coloris picker is configured with: the palette as swatches and
  # every label it shows or announces, in the user's language. Rendered into a
  # data attribute and read by expert_agile_colors.js, so the page carries no
  # inline script.
  def expert_agile_coloris_config
    {
      :swatches => ExpertAgileColor::SWATCHES,
      :defaultColor => ExpertAgileColor::PALETTE['blue'],
      :clearLabel => l(:label_expert_agile_color_clear),
      :closeLabel => l(:button_close),
      :a11y => {
        :open => l(:label_expert_agile_color_a11y_open),
        :close => l(:button_close),
        :clear => l(:label_expert_agile_color_clear),
        :marker => l(:label_expert_agile_color_a11y_marker),
        :hueSlider => l(:label_expert_agile_color_a11y_hue),
        :alphaSlider => l(:label_expert_agile_color_a11y_alpha),
        :input => l(:label_expert_agile_color_a11y_input),
        :format => l(:label_expert_agile_color_a11y_format),
        :swatch => l(:label_expert_agile_color_a11y_swatch),
        :instruction => l(:label_expert_agile_color_a11y_instruction)
      }
    }
  end
end
