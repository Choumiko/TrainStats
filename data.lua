data:extend(
  {
    {
      type = "font",
      name = "trainStats_small",
      from = "default",
      size = 13
    },
    {
      type ="font",
      name = "trainStats_small_bold",
      from = "default-bold",
      size = 13
    },
  })

data.raw["gui-style"].default["trainStats_label"] =
  {
    type = "label_style",
    font = "trainStats_small",
    font_color = {r=1, g=1, b=1},
    top_padding = 0,
    bottom_padding = 0,
    left_padding = 15,
    right_padding = 5
  }

data.raw["gui-style"].default["trainStats_button"] =
  {
    type = "button_style",
    parent = "button_style",
    font = "trainStats_small_bold",
    left_click_sound =
    {
      {
        filename = "__core__/sound/gui-click.ogg",
        volume = 1
      }
    }
  }

data.raw["gui-style"].default["trainStats_table"] =
  {
    type = "table_style",
    parent = "table_style",
    --cell_spacing = 50,
    align = "right"
  }
