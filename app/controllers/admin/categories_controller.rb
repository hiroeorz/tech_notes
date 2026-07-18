# typed: true

module Admin
  class CategoriesController < BaseController
    def index
      @categories = Category.ordered
    end

    def new
      @category = Category.new
    end

    def create
      @category = Category.new(category_params)

      if @category.save
        redirect_to admin_categories_path, notice: t("flash.admin.categories.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @category = Category.find(params[:id])
    end

    def update
      @category = Category.find(params[:id])

      if @category.update(category_params)
        redirect_to admin_categories_path, notice: t("flash.admin.categories.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @category = Category.find(params[:id])
      @category.destroy
      redirect_to admin_categories_path, notice: t("flash.admin.categories.destroyed")
    rescue ActiveRecord::DeleteRestrictionError
      redirect_to admin_categories_path, alert: t("flash.admin.categories.restricted")
    end

    private

    def category_params
      params.require(:category).permit(:name, :name_en, :slug, :icon_key, :position)
    end
  end
end
