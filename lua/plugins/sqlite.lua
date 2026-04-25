return {                                                                                 
  "Maxteabag/sqlit.nvim",                                                         
  opts = {
    theme = "sqlit"
  },                                                                      
  cmd = "Sqlit",                                                                  
  keys = {                                                                        
    { "<leader>D", function() require("sqlit").open() end, desc = "Database (sqlit)" },                                                                       
  },                                                                              
}
