class NetsvcsController < ApplicationController
  def index
    @search = Netsvc.search params[:search]
    @netsvcs = @search.paginate(:page => params[:page])
  end

  def new
    @netsvc = Netsvc.new
  end

  def create
    @netsvc = Netsvc.new(params[:netsvc])
    if @netsvc.save
      flash[:foreman_notice] = "Successfully created network database"
      redirect_to netsvcs_url
    else
      render :action => 'new'
    end
  end

  def edit
    @netsvc = Netsvc.find(params[:id])
  end

  def update
    @netsvc = Netsvc.find(params[:id])
    if @netsvc.update_attributes(params[:netsvc])
      flash[:foreman_notice] = "Successfully updated network database"
      redirect_to netsvcs_url
    else
      render :action => 'edit'
    end
  end

  def destroy
    @netsvc = Netsvc.find(params[:id])
    @netsvc.destroy
    flash[:foreman_notice] = "Successfully destroyed network database"
    redirect_to netsvcs_url
  end
end
